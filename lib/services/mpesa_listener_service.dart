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

/// Watches Appwrite for M-PESA STK confirmations using Realtime and Polling.
class MpesaListenerService {
  static final MpesaListenerService instance = MpesaListenerService._internal();
  MpesaListenerService._internal();

  static const Duration pollInterval = Duration(seconds: 30);

  final _db       = LocalDb.instance;
  final _client   = AppwriteClient.instance;

  final _controller = StreamController<MpesaConfirmation>.broadcast();
  Stream<MpesaConfirmation> get confirmations => _controller.stream;

  RealtimeSubscription? _subscription;
  Timer? _pollTimer;
  bool   _started = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

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

  // ── Strategy 1: Appwrite Realtime (UPDATED FOR 1.8.0) ──────────────────────

  void _subscribeRealtime() {
    try {
      final realtime = AppwriteClient.instance.realtime;

      // MIGRATION: The channel string must use 'tables' and 'rows' instead of 
      // 'collections' and 'documents' to match the 1.8.0+ server events.
      _subscription = realtime.subscribe([
        'databases.${AppwriteClient.kDatabaseId}'
        '.tables.${AppwriteClient.colFinancials}'
        '.rows',
      ]);

      _subscription!.stream.listen(
        _onRealtimeEvent,
        onError: (e) {
          Log.e('[MpesaListener] Realtime error: $e');
        },
        onDone: () {
          Log.i('[MpesaListener] Realtime socket closed — reconnecting.');
          Future.delayed(const Duration(seconds: 5), () {
            if (_started) _subscribeRealtime();
          });
        },
        cancelOnError: false,
      );

      Log.i('[MpesaListener] Realtime subscribed to financials table.');
    } catch (e) {
      Log.e('[MpesaListener] Realtime subscribe failed: $e');
    }
  }

  void _onRealtimeEvent(RealtimeMessage message) {
    // Only care about update events
    final isUpdate = message.events.any((e) => e.contains('.update'));
    if (!isUpdate) return;

    final payload = message.payload;
    final status  = payload['payment_status'] as String?;

    if (status != 'paid') return;

    final txnId   = payload['transaction_id'] as String?;
    final receipt = payload['mpesa_receipt'] as String?;
    final amount  = (payload['amount'] as num?)?.toDouble();

    if (txnId == null || receipt == null || amount == null) return;

    // Check ownership
    if (payload['created_by'] != SessionManager.instance.currentUserId) return;

    Log.i('[MpesaListener] Realtime confirmed: $txnId');
    _applyConfirmation(txnId, receipt, amount);
  }

  // ── Strategy 2: Polling fallback (UPDATED FOR 1.8.0) ───────────────────────

  void _startPolling() {
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollPending());
    _pollPending();
  }

  Future<void> _pollPending() async {
    if (!await _isOnline()) return;
    
    try {
      final db = await _db.database;

      final rows = await db.query(
        'financials',
        columns: ['transaction_id', 'amount'],
        where: "payment_status = 'pending' "
               "AND checkout_request_id IS NOT NULL "
               "AND created_by = ?",
        whereArgs: [SessionManager.instance.currentUserId],
      );

      if (rows.isEmpty) return;

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
      // MIGRATION: getRow replaces getDocument
      final row = await _client.tablesDB.getRow(
        databaseId:   AppwriteClient.kDatabaseId,
        tableId:      AppwriteClient.colFinancials,
        rowId:        transactionId,
      );

      final status  = row.data['payment_status'] as String?;
      final receipt = row.data['mpesa_receipt']  as String?;

      if (status == 'paid' && receipt != null && receipt.isNotEmpty) {
        Log.i('[MpesaListener] Poll confirmed: $transactionId');
        _applyConfirmation(transactionId, receipt, amount);
      }
    } on AppwriteException catch (e) {
      if (e.code == 404) return;
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

      final check = await db.query(
        'financials',
        columns: ['payment_status'],
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      
      if (check.isEmpty || check.first['payment_status'] == 'paid') return;

      await db.transaction((txn) async {
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

        // Re-queue for local sync pass
        await _db.addToQueue(
          txn,
          recordId:  transactionId,
          tableName: 'financials',
          operation: 'UPDATE',
        );
      });

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