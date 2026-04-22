import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/appwrite_client.dart';
import '../core/local_db.dart';
import '../core/logger.dart';
import 'image_service.dart';
import 'image_sync_service.dart';

/// Pulls records from every Appwrite table into local SQLite.
class DownSyncService {
  static final DownSyncService instance = DownSyncService._();
  DownSyncService._();

  static const int _pageSize = 100;
  static const _uuid = Uuid();

  // Tables in dependency order (parents before children)
  static const List<_CollectionConfig> _collections = [
    _CollectionConfig(collection: AppwriteClient.colLedger, table: 'ledger_entries', primaryKey: 'event_id'),
    _CollectionConfig(collection: AppwriteClient.colAssets, table: 'assets', primaryKey: 'asset_id'),
    _CollectionConfig(collection: AppwriteClient.colInventory, table: 'inventory', primaryKey: 'item_id'),
    _CollectionConfig(collection: AppwriteClient.colFinancials, table: 'financials', primaryKey: 'transaction_id'),
    _CollectionConfig(collection: AppwriteClient.colPartialPayments, table: 'partial_payments', primaryKey: 'payment_id'),
    _CollectionConfig(collection: AppwriteClient.colAssetEvents, table: 'asset_events', primaryKey: 'event_id'),
    _CollectionConfig(collection: AppwriteClient.colMilkLogs, table: 'milk_logs', primaryKey: 'log_id'),
    _CollectionConfig(collection: AppwriteClient.colAssetImages, table: 'asset_images', primaryKey: 'image_id'),
    _CollectionConfig(collection: AppwriteClient.colFlockLogs, table: 'flock_logs', primaryKey: 'log_id'),
  ];

  Future<int> pullAll(String userId) async {
    int totalWritten = 0;
    int totalConflicts = 0;
    final pullStartedAt = DateTime.now().toUtc().toIso8601String();

    for (final cfg in _collections) {
      try {
        final result = await _pullCollection(cfg, userId);
        totalWritten += result.written;
        totalConflicts += result.conflicts;
      } catch (e) {
        Log.e('[DownSync] Failed to pull ${cfg.table}: $e');
      }
    }

    Log.i('[DownSync] Pull complete — $totalWritten written, $totalConflicts conflict(s).');

    for (final cfg in _collections) {
      await LocalDb.instance.setLastSyncedAt(cfg.collection, pullStartedAt);
    }

    await _downloadThumbnails();
    return totalWritten;
  }

  Future<void> _downloadThumbnails() async {
    final db = await LocalDb.instance.database;
    final rows = await db.query(
      'asset_images',
      where: "sort_order = 0 AND appwrite_file_id IS NOT NULL AND (local_path IS NULL OR local_path = '')",
    );

    if (rows.isEmpty) return;
    for (final row in rows) {
      final image = FarmImage.fromMap(row);
      try {
        await ImageSyncService.instance.fetchAndRecache(image);
      } catch (e) {
        Log.e('[DownSync] Thumbnail download failed ${image.imageId}: $e');
      }
    }
  }

  Future<_PullResult> _pullCollection(_CollectionConfig cfg, String userId) async {
    final cursor = await LocalDb.instance.getLastSyncedAt(cfg.collection);
    final isFirstSync = cursor == null;

    final tablesDB = AppwriteClient.instance.tablesDB;
    int written = 0;
    int conflicts = 0;
    int offset = 0;

    while (true) {
      final queries = [
        Query.equal('created_by', userId),
        Query.limit(_pageSize),
        Query.offset(offset),
        Query.orderAsc('created_at'),
      ];

      if (!isFirstSync) queries.add(Query.greaterThan('created_at', cursor));

      // MIGRATION: listRows replaces listDocuments (or the incorrect getRow)
      final result = await tablesDB.listRows(
        databaseId: AppwriteClient.kDatabaseId,
        tableId: cfg.collection,
        queries: queries,
      );

      if (result.rows.isEmpty) break;

      final db = await LocalDb.instance.database;
      final seenInPage = <String>{};

      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        for (final row in result.rows) {
          final incoming = _documentToRow(row.data, cfg);
          final recordId = incoming[cfg.primaryKey]?.toString();

          if (recordId == null || (incoming['created_by'] != userId)) continue;
          if (!seenInPage.add(recordId)) continue;

          final existing = await db.query(cfg.table, where: '${cfg.primaryKey} = ?', whereArgs: [recordId], limit: 1);

          if (existing.isNotEmpty) {
            final localRow = Map<String, dynamic>.from(existing.first);
            if (_isDifferent(localRow, incoming)) {
              conflicts++;
              // Fire and forget conflict recording to Appwrite
              _recordConflict(table: cfg.table, recordId: recordId, localRow: localRow, remoteRow: incoming, userId: userId);
            }
          }

          await db.insert(cfg.table, incoming, conflictAlgorithm: ConflictAlgorithm.replace);
          written++;
        }
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      if (result.rows.length < _pageSize) break;
      offset += _pageSize;
    }

    return _PullResult(written: written, conflicts: conflicts);
  }

  Future<void> _recordConflict({
    required String table,
    required String recordId,
    required Map<String, dynamic> localRow,
    required Map<String, dynamic> remoteRow,
    required String userId,
  }) async {
    final now = DateTime.now().toUtc();
    final diffFields = <String, dynamic>{};
    
    for (final key in {...localRow.keys, ...remoteRow.keys}) {
      if (localRow[key]?.toString() != remoteRow[key]?.toString()) {
        diffFields[key] = {'local': localRow[key], 'remote': remoteRow[key]};
      }
    }

    final conflictId = _uuid.v4();

    try {
      // MIGRATION: Using the new upsertRow for conflict logging
      await AppwriteClient.instance.tablesDB.upsertRow(
        databaseId: AppwriteClient.kDatabaseId,
        tableId: AppwriteClient.colSyncConflicts,
        rowId: conflictId,
        data: {
          'conflict_id': conflictId,
          'table_name': table,
          'record_id': recordId,
          'user_id': userId,
          'resolution': 'appwrite_wins',
          'diff_json': jsonEncode(diffFields),
          'local_json': jsonEncode(localRow),
          'remote_json': jsonEncode(remoteRow),
          'conflict_at': now.toIso8601String(),
          'created_by': userId,
          'created_at': now.toIso8601String(),
        },
      );
    } catch (e) {
      Log.e('[DownSync] Conflict record failed: $e');
    }
  }

  bool _isDifferent(Map<String, dynamic> local, Map<String, dynamic> remote) {
    for (final key in remote.keys) {
      if (local[key]?.toString() != remote[key]?.toString()) return true;
    }
    return false;
  }

  static const _lowercaseFields = {
    'type', 'status', 'category', 'unit', 'session',
    'payment_method', 'payment_status', 'transaction_type', 'method',
    'upload_status', 'entity_type',
  };

  Map<String, dynamic> _documentToRow(Map<String, dynamic> data, _CollectionConfig cfg) {
    final row = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.key.startsWith('\$')) continue; 
      var val = entry.value;
      if (entry.key == 'is_kra_certified') {
        val = (val == true) ? 1 : 0;
      } else if (val is String && _lowercaseFields.contains(entry.key)) {
        val = val.toLowerCase();
      }
      row[entry.key] = val;
    }
    return row;
  }
}

class _PullResult {
  final int written;
  final int conflicts;
  const _PullResult({required this.written, required this.conflicts});
}

class _CollectionConfig {
  final String collection;
  final String table;
  final String primaryKey;
  const _CollectionConfig({required this.collection, required this.table, required this.primaryKey});
}