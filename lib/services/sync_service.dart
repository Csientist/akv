import 'package:appwrite/appwrite.dart';
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

  // Static lock to prevent multiple sync loops from overlapping
  static bool _isSyncing = false;
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
  Future<void> fullSync() async {
    if (_isSyncing) return;
    await _runSyncLoop();
  }

  Future<void> _runSyncLoop() async {
    // Gate 1: Connectivity
    final connectivityResults = await Connectivity().checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      Log.w('[Sync] Offline — skipping sync loop.');
      return;
    }

    // Gate 2: Session Check
    final hasSession = await PinService.instance.hasSession();
    if (!hasSession) {
      Log.w('[Sync] No Appwrite session — skipping up-sync.');
      return;
    }

    _isSyncing = true;
    Log.i('[Sync] Starting sync loop...');

    try {
      final queue = await _db.getPendingQueue();

      if (queue.isNotEmpty) {
        Log.i('[Sync] ${queue.length} item(s) to push.');
        for (final item in queue) {
          await _syncItem(item);
        }
        // Upload image files to Storage
        await ImageSyncService.instance.uploadPending();
      }

      // ── Down-sync: pull remote changes ────────────────────────────────────
      final userId = SessionManager.instance.isLoggedIn
          ? SessionManager.instance.currentUserId
          : null;
      
      if (userId != null) {
        await DownSyncService.instance.pullAll(userId);
      }
    } catch (e, stackTrace) {
      Log.e('[Sync] Fatal sync error: $e\n$stackTrace');
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

    // Poison pill defense
    if (retryCount >= _maxRetries) {
      Log.e('[Sync] 🛑 Item $queueId ($tableName) failed max retries.');
      await _db.updateQueueStatus(queueId, 'failed');
      return;
    }

    // Special Case: asset_images DELETE
    if (tableName == 'asset_images') {
      try {
        // 1. Remove file from Storage
        await ImageSyncService.instance.deleteFile(recordId);
        
        // 2. Remove metadata row from the Table
        try {
          await _remote.tablesDB.deleteRow(
            databaseId: AppwriteClient.kDatabaseId,
            tableId:    AppwriteClient.colAssetImages,
            rowId:      recordId,
          );
        } on AppwriteException catch (e) {
          if (e.code != 404) rethrow; // 404 means already deleted on server, which is a win
        }
        
        await _db.removeFromQueue(queueId);
        Log.i('[Sync] ✓ Deleted image $recordId');
      } catch (e) {
        await _db.markQueueRetry(queueId, retryCount);
        Log.e('[Sync] ✗ Image delete failed: $e');
      }
      return;
    }

    // Standard Case: Upsert (Update or Create)
    try {
      final db = await _db.database;
      final rows = await db.query(
        tableName,
        where: _primaryKeyWhereClause(tableName),
        whereArgs: [recordId],
        limit: 1,
      );

      if (rows.isEmpty) {
        Log.w('[Sync] $recordId missing locally — dropping from queue.');
        await _db.removeFromQueue(queueId);
        return;
      }

      final rawData  = Map<String, dynamic>.from(rows.first);
      final tableId  = _tableToId(tableName);
      final sanitized = _sanitizeForAppwrite(rawData, tableName);

      // MIGRATION: Uses the refactored native upsertRow under the hood
      await _remote.upsertDocument(
        collectionId: tableId,
        documentId:   recordId,
        data:         sanitized,
      );

      await _db.removeFromQueue(queueId);
      Log.i('[Sync] ✓ Synced $tableName/$recordId');

    } catch (e) {
      await _db.markQueueRetry(queueId, retryCount);
      Log.e('[Sync] ✗ Failed $tableName/$recordId (Attempt ${retryCount + 1}): $e');
    }
  }

  // ── Table Routing ──────────────────────────────────────────────────────────

  String _tableToId(String tableName) {
    switch (tableName) {
      case 'ledger_entries': return AppwriteClient.colLedger;
      case 'assets':         return AppwriteClient.colAssets;
      case 'inventory':      return AppwriteClient.colInventory;
      case 'financials':     return AppwriteClient.colFinancials;
      case 'asset_events':   return AppwriteClient.colAssetEvents;
      case 'milk_logs':      return AppwriteClient.colMilkLogs;
      case 'partial_payments': return AppwriteClient.colPartialPayments;
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
      case 'partial_payments': return 'payment_id = ?';
      default: throw Exception('[Sync] Unknown PK for: $tableName');
    }
  }

  // ── Sanitization ───────────────────────────────────────────────────────────

  Map<String, dynamic> _sanitizeForAppwrite(Map<String, dynamic> data, String tableName) {
    final out = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      var   val = entry.value;

      if (key == 'id' || key == 'queue_id') continue;

      if (key == 'is_kra_certified') {
        out[key] = val == 1;
        continue;
      }

      if (key == 'metadata') {
        if (val != null && val.toString().isNotEmpty) {
          out[key] = val.toString(); 
        }
        continue;
      }

      if (val == null) continue;
      out[key] = val;
    }
    return out;
  }

  // ── Connectivity listener ──────────────────────────────────────────────────

  void listenForConnectivity() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none)) {
        Log.i('[Sync] Network restored — triggering sync.');
        fullSync();
      }
    });
  }
}