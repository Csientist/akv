import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/appwrite_client.dart';
import '../core/local_db.dart';
import '../core/logger.dart';
import '../services/session_manager.dart';

// ── Confirmation result ────────────────────────────────────────────────────────

class MpesaConfirmation {
  final String transactionId;
  final String mpesaReceipt;
  final double amount;

  const MpesaConfirmation({
    required this.transactionId,
    required this.mpesaReceipt,
    required this.amount,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Watches Appwrite for M-PESA STK confirmations and writes them back to
/// local SQLite. Uses two complementary strategies:
///
///   1. Realtime WebSocket  — instant push from Appwrite when the Go function
///      updates the financials document after Safaricom's callback.
///
///   2. Polling fallback    — queries Appwrite every [pollInterval] for any
///      financials rows that are still pending locally but may have been
///      confirmed server-side. Catches cases where the Realtime socket was
///      offline when the callback arrived.
///
/// Consumers listen to [confirmations] stream and refresh their UI on events.

class MpesaListenerService {
  static final MpesaListenerService instance =
      MpesaListenerService._internal();
  MpesaListenerService._internal();

  static const Duration pollInterval = Duration(seconds: 30);

  final _db     = LocalDb.instance;
  final _client = AppwriteClient.instance;

  // Public stream — UI layers subscribe to this
  final _controller =
      StreamController<MpesaConfirmation>.broadcast();
  Stream<MpesaConfirmation> get confirmations => _controller.stream;

  RealtimeSubscription? _subscription;
  Timer? _pollTimer;
  bool   _started = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call once after AppwriteClient.init() and login — typically in AuthGate
  /// after _onUnlocked(), so we have a valid session before subscribing.
  void start() {
    if (_started) return;
    _started = true;
    Log.i('[MpesaListener] Starting.');
    _subscribeRealtime();
    _startPolling();
  }

  void stop() {
    _subscription?.close();
    _subscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _started = false;
    Log.i('[MpesaListener] Stopped.');
  }

  void dispose() {
    stop();
    _controller.close();
  }

  // ── Connectivity helper ────────────────────────────────────────────────────

  Future<bool> _isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  // ── Strategy 1: Appwrite Realtime ──────────────────────────────────────────

  void _subscribeRealtime() {
    try {
      final realtime = AppwriteClient.instance.realtime;

      // Subscribe to any update on the financials collection.
      // We filter to relevant events in the handler.
      _subscription = realtime.subscribe([
        'databases.${AppwriteClient.kDatabaseId}'
        '.collections.${AppwriteClient.colFinancials}'
        '.documents',
      ]);

      _subscription!.stream.listen(
        _onRealtimeEvent,
        onError: (e) {
          Log.e('[MpesaListener] Realtime error: $e — polling will cover.');
          // Don't rethrow — polling is the safety net
        },
        onDone: () {
          Log.i('[MpesaListener] Realtime socket closed — reconnecting.');
          // Re-subscribe after a short delay
          Future.delayed(const Duration(seconds: 5), () {
            if (_started) _subscribeRealtime();
          });
        },
        cancelOnError: false,
      );

      Log.i('[MpesaListener] Realtime subscribed to financials.');
    } catch (e) {
      Log.e('[MpesaListener] Realtime subscribe failed: $e');
    }
  }

  void _onRealtimeEvent(RealtimeMessage message) {
    // Only care about update events (not create/delete)
    final events = message.events;
    final isUpdate = events.any((e) => e.contains('.update'));
    if (!isUpdate) return;

    final payload = message.payload;
    final status  = payload['payment_status'] as String?;

    // Only act when Appwrite says paid
    if (status != 'paid') return;

    final txnId  = payload['transaction_id'] as String?;
    final receipt = payload['mpesa_receipt'] as String?;
    final amount  = (payload['amount'] as num?)?.toDouble();

    if (txnId == null || receipt == null || amount == null) return;

    // Only handle records owned by the current user
    final createdBy = payload['created_by'] as String?;
    if (createdBy != SessionManager.instance.currentUserId) return;

    Log.i('[MpesaListener] Realtime confirmed: $txnId receipt: $receipt');
    _applyConfirmation(txnId, receipt, amount);
  }

  // ── Strategy 2: Polling fallback ───────────────────────────────────────────

  void _startPolling() {
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollPending());
    // Also poll immediately on start to catch anything missed while offline
    _pollPending();
  }

  Future<void> _pollPending() async {
    if (!await _isOnline()) {
      Log.i('[MpesaListener] Offline — skipping poll.');
      return;
    }
    try {
      final db = await _db.database;

      // Find all local financials that are still pending and have a
      // checkout_request_id (i.e. an STK Push was sent for them)
      final rows = await db.query(
        'financials',
        columns: ['transaction_id', 'checkout_request_id', 'amount'],
        where: "payment_status = 'pending' "
            "AND checkout_request_id IS NOT NULL "
            "AND created_by = ?",
        whereArgs: [SessionManager.instance.currentUserId],
      );

      if (rows.isEmpty) return;

      Log.i('[MpesaListener] Polling ${rows.length} pending STK transaction(s).');

      for (final row in rows) {
        final txnId = row['transaction_id'] as String;
        final amount = (row['amount'] as num).toDouble();
        await _fetchAndApply(txnId, amount);
      }
    } catch (e) {
      Log.e('[MpesaListener] Poll error: $e');
    }
  }

  Future<void> _fetchAndApply(String transactionId, double amount) async {
    try {
      final doc = await _client.databases.getDocument(
        databaseId:   AppwriteClient.kDatabaseId,
        collectionId: AppwriteClient.colFinancials,
        documentId:   transactionId,
      );

      final status  = doc.data['payment_status'] as String?;
      final receipt = doc.data['mpesa_receipt']  as String?;

      if (status == 'paid' && receipt != null && receipt.isNotEmpty) {
        Log.i('[MpesaListener] Poll confirmed: $transactionId receipt: $receipt');
        _applyConfirmation(transactionId, receipt, amount);
      }
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        // Document not yet synced to Appwrite — normal, skip silently
        return;
      }
      Log.e('[MpesaListener] Fetch error for $transactionId: ${e.message}');
    } catch (e) {
      Log.e('[MpesaListener] Unexpected fetch error: $e');
    }
  }

  // ── Write confirmation to SQLite ───────────────────────────────────────────

  Future<void> _applyConfirmation(
      String transactionId, String mpesaReceipt, double amount) async {
    try {
      final db = await _db.database;

      // Guard: don't write twice if both Realtime and poll fire for same txn
      final check = await db.query(
        'financials',
        columns: ['payment_status'],
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (check.isEmpty) return;
      if (check.first['payment_status'] == 'paid') {
        Log.i('[MpesaListener] $transactionId already confirmed — skipping.');
        return;
      }

      await db.transaction((txn) async {
        // 1. Mark financial as paid
        await txn.update(
          'financials',
          {
            'payment_status': 'paid',
            'amount_paid':    amount,
            'mpesa_receipt':  mpesaReceipt,
          },
          where: 'transaction_id = ?',
          whereArgs: [transactionId],
        );

        // 2. Re-queue the financial so the updated row syncs back to Appwrite
        //    (in case the Go function only updated Appwrite directly and the
        //     local record was never updated before this write)
        await _db.addToQueue(
          txn,
          recordId:  transactionId,
          tableName: 'financials',
          operation: 'UPDATE',
        );
      });

      Log.i('[MpesaListener] Applied confirmation for $transactionId.');

      // Notify UI listeners
      _controller.add(MpesaConfirmation(
        transactionId: transactionId,
        mpesaReceipt:  mpesaReceipt,
        amount:        amount,
      ));
    } catch (e) {
      Log.e('[MpesaListener] Failed to apply confirmation: $e');
    }
  }
}