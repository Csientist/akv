import '../core/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/local_db.dart';
import '../core/appwrite_client.dart';
import 'pin_service.dart';
import 'image_sync_service.dart';
import 'down_sync_service.dart';
import 'session_manager.dart';

class SyncService {
  final LocalDb _db;
  final AppwriteClient _remote;
  bool _isSyncing = false;

  static const int _maxRetries = 5;

  SyncService({LocalDb? db, AppwriteClient? remote})
      : _db = db ?? LocalDb.instance,
        _remote = remote ?? AppwriteClient.instance;

  // ── Entry points ───────────────────────────────────────────────────────────

  /// Non-blocking up-sync only (connectivity listener trigger).
  void processQueue() {
    if (_isSyncing) return;
    _runSyncLoop();
  }

  /// Full bidirectional sync: push local changes first, then pull remote.
  /// Call this on login/unlock and on AppRefreshService ticks.
  Future<void> fullSync() async {
    if (_isSyncing) return;
    await _runSyncLoop();
  }

  Future<void> _runSyncLoop() async {
    // Gate 1: Connectivity
    final connectivityResults = await Connectivity().checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      Log.w('[Sync] Offline — will retry when connected.');
      return;
    }

    // Gate 2: Must have a valid Appwrite session before pushing anything.
    // Without this, every record would get a 401 and burn through retries.
    final hasSession = await PinService.instance.hasSession();
    if (!hasSession) {
      Log.w('[Sync] No Appwrite session — skipping until user logs in.');
      return;
    }

    _isSyncing = true;
    Log.i('[Sync] Starting sync loop...');

    try {
      final queue = await _db.getPendingQueue();

      if (queue.isNotEmpty) {
        Log.i('[Sync] ${queue.length} item(s) to sync.');
        for (final item in queue) {
          await _syncItem(item);
        }
        // Upload pending image files to Appwrite Storage
        await ImageSyncService.instance.uploadPending();
      } else {
        Log.i('[Sync] Up-sync queue empty.');
      }

      // ── Down-sync: pull remote changes into local SQLite ──────────────────
      // Always runs — even on fresh install with empty queue.
      // Runs after up-sync so we don't overwrite our own just-pushed records.
      final userId = SessionManager.instance.isLoggedIn
          ? SessionManager.instance.currentUserId
          : null;
      if (userId != null) {
        await DownSyncService.instance.pullAll(userId);
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

    // asset_images rows are Storage uploads/deletes, not Database documents.
    // ImageSyncService.uploadPending() handles CREATE — here we only handle DELETE.
    if (tableName == 'asset_images') {
      try {
        // recordId for DELETE is the image_id, which equals the Appwrite file ID.
        await ImageSyncService.instance.deleteFile(recordId);
        await _db.removeFromQueue(queueId);
        Log.i('[Sync] ✓ Deleted image file $recordId from Appwrite Storage');
      } catch (e) {
        await _db.markQueueRetry(queueId, retryCount);
        Log.e('[Sync] ✗ Failed to delete image $recordId: $e');
      }
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
        Log.w('[Sync] $recordId missing in $tableName — dropping from queue.');
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
      case 'ledger_entries': return AppwriteClient.colLedger;
      case 'assets':         return AppwriteClient.colAssets;
      case 'inventory':      return AppwriteClient.colInventory;
      case 'financials':     return AppwriteClient.colFinancials;
      case 'asset_events':   return AppwriteClient.colAssetEvents;
      case 'milk_logs':      return AppwriteClient.colMilkLogs;
      default: throw Exception('[Sync] Unknown table: $tableName');
    }
  }

  String _primaryKeyWhereClause(String tableName) {
    switch (tableName) {
      case 'ledger_entries': return 'event_id = ?';
      case 'assets':         return 'asset_id = ?';
      case 'inventory':      return 'item_id = ?';
      case 'financials':     return 'transaction_id = ?';
      case 'asset_events':   return 'event_id = ?';
      case 'milk_logs':      return 'log_id = ?';
      default: throw Exception('[Sync] Unknown table: $tableName');
    }
  }

  // ── Sanitization ───────────────────────────────────────────────────────────

  Map<String, dynamic> _sanitizeForAppwrite(
      Map<String, dynamic> data, String tableName) {
    final out = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      var   val = entry.value;

      // Strip SQLite-internal fields Appwrite doesn't want in the document body
      if (key == 'id' || key == 'queue_id') continue;

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