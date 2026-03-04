import 'dart:developer' as dev;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/local_db.dart';
import '../core/appwrite_client.dart';

class SyncService {
  final LocalDb _db;
  final AppwriteClient _remote;
  bool _isSyncing = false;
  
  // Hardening: Prevent infinite loops on bad data (e.g., 400 Bad Request)
  static const int _maxRetries = 5;

  SyncService({LocalDb? db, AppwriteClient? remote})
      : _db = db ?? LocalDb.instance,
        _remote = remote ?? AppwriteClient.instance;

  // ── Entry point (non-blocking) ─────────────────────────────────────────────
  void processQueue() {
    if (_isSyncing) return; // Prevent concurrent sync collisions
    _runSyncLoop();
  }

  Future<void> _runSyncLoop() async {
    // Step 1: Check connectivity (Hardened for connectivity_plus ^6.0.0)
    final connectivityResults = await Connectivity().checkConnectivity();

    print('📡 Network check: $connectivityResults');

    if (connectivityResults.contains(ConnectivityResult.none)) {
      print('📴 App thinks it is offline! Aborting sync.'); // ADD THIS
      dev.log('[SyncService] Offline — queue will retry when connected.');
      return;
    }

    _isSyncing = true;
    dev.log('[SyncService] Starting sync loop...');

    try {
      // Step 2: Fetch all pending items (Ideally limit this to 50 at a time in LocalDb)
      final queue = await _db.getPendingQueue();
      if (queue.isEmpty) {
        dev.log('[SyncService] Queue is empty. Nothing to sync.');
        return;
      }
      
      dev.log('[SyncService] ${queue.length} item(s) to sync.');

      for (final item in queue) {
        await _syncItem(item);
      }
    } catch (e, stackTrace) {
      dev.log('[SyncService] Fatal error in sync loop: $e\n$stackTrace');
    } finally {
      _isSyncing = false;
      dev.log('[SyncService] Sync loop complete.');
    }
  }

  Future<void> _syncItem(Map<String, dynamic> queueRow) async {
    final queueId    = queueRow['queue_id'] as int;
    final recordId   = queueRow['record_id'] as String;
    final tableName  = queueRow['table_name'] as String;
    final retryCount = (queueRow['retry_count'] as int?) ?? 0;

    // Hardening: The "Poison Pill" Defense
    if (retryCount >= _maxRetries) {
      dev.log('[SyncService] 🛑 Item $queueId exceeded max retries. Marking as failed.');
      // Assuming you add an updateQueueStatus method to LocalDb to prevent infinite loops
      await _db.updateQueueStatus(queueId, 'failed'); 
      return;
    }

    try {
      // Step 3: Load the actual record from the local table
      final db = await _db.database;
      final rows = await db.query(
        tableName,
        where: _primaryKeyWhereClause(tableName),
        whereArgs: [recordId],
        limit: 1,
      );

      if (rows.isEmpty) {
        // Record was deleted locally before it could sync — remove from queue silently
        dev.log('[SyncService] Record $recordId missing in $tableName. Dropping from queue.');
        await _db.removeFromQueue(queueId);
        return;
      }

      final rawData = Map<String, dynamic>.from(rows.first);
      final collectionId = _tableToCollection(tableName);
      final sanitizedData = _sanitizeForAppwrite(rawData);

      // Step 4: Push to Appwrite
      await _remote.upsertDocument(
        collectionId: collectionId,
        documentId: recordId,
        data: sanitizedData,
      );

      // Step 5: On success — remove from queue
      await _db.removeFromQueue(queueId);
      dev.log('[SyncService] ✓ Synced $tableName/$recordId');
      
    } catch (e) {
      // Step 5 (failure): Increment retry count (Exponential backoff logic should exist in LocalDb)
      final newRetryCount = retryCount + 1;
      await _db.markQueueRetry(queueId, newRetryCount);
      dev.log('[SyncService] ✗ Failed $tableName/$recordId (Attempt $newRetryCount/$_maxRetries): $e');
    }
  }

  /// Map local table names to Appwrite collection IDs.
  String _tableToCollection(String tableName) {
    switch (tableName) {
      case 'ledger_entries': return AppwriteClient.colLedger;
      case 'assets':         return AppwriteClient.colAssets;
      case 'inventory':      return AppwriteClient.colInventory;
      case 'financials':     return AppwriteClient.colFinancials;
      default: throw Exception('Unknown table: $tableName');
    }
  }

  /// Each table has a different primary key column name.
  String _primaryKeyWhereClause(String tableName) {
    switch (tableName) {
      case 'ledger_entries': return 'event_id = ?';
      case 'assets':         return 'asset_id = ?';
      case 'inventory':      return 'item_id = ?';
      case 'financials':     return 'transaction_id = ?';
      default: throw Exception('Unknown table: $tableName');
    }
  }

  /// Hardening: Ensure SQLite types map perfectly to Appwrite schema requirements
  Map<String, dynamic> _sanitizeForAppwrite(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    
    for (final entry in data.entries) {
      var val = entry.value;

      // 1. Boolean Conversion (SQLite stores bools as integers)
      if (entry.key == 'is_kra_certified') {
        val = (val == 1);
      } 
      
      // 2. Strip internal SQLite IDs that Appwrite doesn't want inside the document body
      // We don't strip the actual Primary Keys (like asset_id) because we mapped them above!
      if (entry.key == 'id' || entry.key == 'queue_id') continue;

      out[entry.key] = val;
    }
    
    return out;
  }

  /// Call this from main.dart to reconnect syncing whenever network returns.
  void listenForConnectivity() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // Hardening: Check if the list contains anything OTHER than 'none'
      if (!results.contains(ConnectivityResult.none)) {
        dev.log('[SyncService] Network restored — triggering sync.');
        processQueue();
      }
    });
  }
}