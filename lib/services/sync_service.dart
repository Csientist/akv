import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/local_db.dart';
import '../core/appwrite_client.dart';
import 'pin_service.dart';
import '../core/logger.dart';


class SyncService {
  final LocalDb _db;
  final AppwriteClient _remote;
  bool _isSyncing = false;

  static const int _maxRetries = 5;

  SyncService({LocalDb? db, AppwriteClient? remote})
      : _db = db ?? LocalDb.instance,
        _remote = remote ?? AppwriteClient.instance;

  // ── Entry point (non-blocking) ─────────────────────────────────────────────

  void processQueue() {
    if (_isSyncing) return;
    _runSyncLoop();
  }

  Future<void> _runSyncLoop() async {
    // Gate 1: Connectivity
    final connectivityResults = await Connectivity().checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      Log.e('[Sync] Offline — will retry when connected.');
      return;
    }

    // Gate 2: Must have a valid Appwrite session before pushing anything.
    // Without this, every record would get a 401 and burn through retries.
    final hasSession = await PinService.instance.hasSession();
    if (!hasSession) {
      Log.e('[Sync] No Appwrite session — skipping until user logs in.');
      return;
    }

    _isSyncing = true;
    Log.i('[Sync] Starting sync loop...');

    try {
      final queue = await _db.getPendingQueue();
      if (queue.isEmpty) {
        Log.i('[Sync] Queue is empty. Nothing to sync.');
        return;
      }

      Log.i('[Sync] ${queue.length} item(s) to sync.');
      for (final item in queue) {
        await _syncItem(item);
      }
    } catch (e, stackTrace) {
      Log.e('[Sync] Fatal error in sync loop: $e\n$stackTrace');
    } finally {
      _isSyncing = false;
      Log.i('[Sync] Sync loop complete.');
    }
  }

  Future<void> _syncItem(Map<String, dynamic> queueRow) async {
    final queueId    = queueRow['queue_id'] as int;
    final recordId   = queueRow['record_id'] as String;
    final tableName  = queueRow['table_name'] as String;
    final retryCount = (queueRow['retry_count'] as int?) ?? 0;

    // Poison pill defence
    if (retryCount >= _maxRetries) {
      Log.e('[Sync] 🛑 Item $queueId exceeded max retries. Marking as failed.');
      await _db.updateQueueStatus(queueId, 'failed');
      return;
    }

    try {
      final db = await _db.database;
      final rows = await db.query(
        tableName,
        where: _primaryKeyWhereClause(tableName),
        whereArgs: [recordId],
        limit: 1,
      );

      if (rows.isEmpty) {
        Log.i('[Sync] $recordId missing in $tableName — dropping from queue.');
        await _db.removeFromQueue(queueId);
        return;
      }

      final rawData      = Map<String, dynamic>.from(rows.first);
      final collectionId = _tableToCollection(tableName);
      final sanitized    = _sanitizeForAppwrite(rawData, tableName);

      await _remote.upsertDocument(
        collectionId: collectionId,
        documentId: recordId,
        data: sanitized,
      );

      await _db.removeFromQueue(queueId);
      Log.i('[Sync] ✓ Synced $tableName/$recordId');

    } catch (e) {
      await _db.markQueueRetry(queueId, retryCount);
      Log.e('[Sync] ✗ Failed $tableName/$recordId '
          '(attempt ${retryCount + 1}/$_maxRetries): $e');
    }
  }

  // ── Table routing ──────────────────────────────────────────────────────────

  String _tableToCollection(String tableName) {
    switch (tableName) {
      case 'ledger_entries':   return AppwriteClient.colLedger;
      case 'assets':           return AppwriteClient.colAssets;
      case 'inventory':        return AppwriteClient.colInventory;
      case 'financials':       return AppwriteClient.colFinancials;
      case 'asset_events':     return AppwriteClient.colAssetEvents;
      case 'milk_logs':        return AppwriteClient.colMilkLogs;
      case 'partial_payments': return AppwriteClient.colPartialPayments;
      default: throw Exception('[Sync] Unknown table: $tableName');
    }
  }

  String _primaryKeyWhereClause(String tableName) {
    switch (tableName) {
      case 'ledger_entries':   return 'event_id = ?';
      case 'assets':           return 'asset_id = ?';
      case 'inventory':        return 'item_id = ?';
      case 'financials':       return 'transaction_id = ?';
      case 'asset_events':     return 'event_id = ?';
      case 'milk_logs':        return 'log_id = ?';
      case 'partial_payments': return 'payment_id = ?';
      default: throw Exception('[Sync] Unknown table: $tableName');
    }
  }

  /// Returns the primary key column name for a table.
  /// This column is used as the Appwrite documentId and must NOT be
  /// included as a field in the document body — Appwrite rejects it.
  String _primaryKeyColumn(String tableName) {
    switch (tableName) {
      case 'ledger_entries':   return 'event_id';
      case 'assets':           return 'asset_id';
      case 'inventory':        return 'item_id';
      case 'financials':       return 'transaction_id';
      case 'asset_events':     return 'event_id';
      case 'milk_logs':        return 'log_id';
      case 'partial_payments': return 'payment_id';
      default:                 return '';
    }
  }

  // ── Sanitization ───────────────────────────────────────────────────────────

  Map<String, dynamic> _sanitizeForAppwrite(
      Map<String, dynamic> data, String tableName) {
    final out   = <String, dynamic>{};
    final pkCol = _primaryKeyColumn(tableName);

    for (final entry in data.entries) {
      final key = entry.key;
      var   val = entry.value;

      // Strip SQLite-internal fields Appwrite doesn't want in the document body.
      // For partial_payments, also strip payment_id — it is used as the documentId
      // but is NOT declared as a collection attribute (unlike other tables where
      // the PK column IS declared as an attribute and must be included in the body).
      if (key == 'id' || key == 'queue_id') continue;
      if (key == pkCol && tableName == 'partial_payments') continue;

      // SQLite stores booleans as 0/1 integers — Appwrite needs true/false
      if (key == 'is_kra_certified') {
        val = val == 1;
        out[key] = val;
        continue;
      }

      // ── metadata / notes fields ───────────────────────────────────────────
      // Appwrite stores these as String (not JSON object) because Appwrite's
      // free-tier doesn't support arbitrary nested JSON attributes.
      // SQLite already stores them as JSON strings, so we pass them through
      // as-is. Null stays null — don't send empty strings for nullable fields.
      if (key == 'metadata') {
        if (val != null && val.toString().isNotEmpty) {
          out[key] = val.toString(); // guaranteed to be the raw JSON string
        }
        // Skip entirely if null — avoids Appwrite rejecting null on non-nullable schema
        continue;
      }

      // Nulls on optional fields: skip rather than sending null, which can
      // cause Appwrite schema validation errors on required-field mismatch
      if (val == null) continue;

      out[key] = val;
    }

    return out;
  }

  // ── Connectivity listener ──────────────────────────────────────────────────

  void listenForConnectivity() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // Hardening: Check if the list contains anything OTHER than 'none'
      if (!results.contains(ConnectivityResult.none)) {
        Log.i('[SyncService] Network restored — triggering sync.');
        processQueue();
      }
    });
  }
}