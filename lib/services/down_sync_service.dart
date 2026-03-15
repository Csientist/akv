import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/appwrite_client.dart';
import '../core/local_db.dart';
import '../core/logger.dart';
import 'image_service.dart';
import 'image_sync_service.dart';

/// Pulls records from every Appwrite collection into local SQLite.
///
/// Strategy:
///   - Cursor-based: stores last_synced_at per collection in sync_meta table.
///   - On first run (null cursor) pulls ALL records for the user.
///   - On subsequent runs pulls only records newer than the cursor.
///   - Conflict resolution: Appwrite wins — remote overwrites local.
///   - Conflicts are written to the sync_conflicts Appwrite DB collection.
///   - Paginated: 100 records per page.
class DownSyncService {
  static final DownSyncService instance = DownSyncService._();
  DownSyncService._();

  static const int _pageSize = 100;
  static const _uuid = Uuid();

  // Collections in dependency order (parents before children)
  static const List<_CollectionConfig> _collections = [
    _CollectionConfig(
      collection: AppwriteClient.colLedger,
      table:      'ledger_entries',
      primaryKey: 'event_id',
    ),
    _CollectionConfig(
      collection: AppwriteClient.colAssets,
      table:      'assets',
      primaryKey: 'asset_id',
    ),
    _CollectionConfig(
      collection: AppwriteClient.colInventory,
      table:      'inventory',
      primaryKey: 'item_id',
    ),
    _CollectionConfig(
      collection: AppwriteClient.colFinancials,
      table:      'financials',
      primaryKey: 'transaction_id',
    ),
    _CollectionConfig(
      collection: AppwriteClient.colPartialPayments,
      table:      'partial_payments',
      primaryKey: 'payment_id',
    ),
    _CollectionConfig(
      collection: AppwriteClient.colAssetEvents,
      table:      'asset_events',
      primaryKey: 'event_id',
    ),
    _CollectionConfig(
      collection: AppwriteClient.colMilkLogs,
      table:      'milk_logs',
      primaryKey: 'log_id',
    ),
    // Image metadata — must come after assets/asset_events so FK refs exist
    _CollectionConfig(
      collection: AppwriteClient.colAssetImages,
      table:      'asset_images',
      primaryKey: 'image_id',
    ),
  ];

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<int> pullAll(String userId) async {
    int totalWritten   = 0;
    int totalConflicts = 0;
    final pullStartedAt = DateTime.now().toUtc().toIso8601String();

    for (final cfg in _collections) {
      try {
        final result = await _pullCollection(cfg, userId);
        totalWritten   += result.written;
        totalConflicts += result.conflicts;
      } catch (e) {
        Log.e('[DownSync] Failed to pull ${cfg.table}: $e');
      }
    }

    Log.i('[DownSync] Pull complete — '
        '$totalWritten written, $totalConflicts conflict(s) recorded.');

    // Advance ALL cursors to pull-start time.
    for (final cfg in _collections) {
      await LocalDb.instance.setLastSyncedAt(cfg.collection, pullStartedAt);
    }

    // After metadata is synced, download thumbnails (sort_order = 0 only)
    // so herd cards show photos immediately without waiting for on-demand load.
    await _downloadThumbnails();

    return totalWritten;
  }

  /// Download the first image (sort_order = 0) for every asset that has an
  /// uploaded image but no local cache file. All other images load on demand
  /// via AssetImageWidget's fetchAndRecache fallback.
  Future<void> _downloadThumbnails() async {
    final db = await LocalDb.instance.database;

    final rows = await db.query(
      'asset_images',
      where: "sort_order = 0 "
             "AND appwrite_file_id IS NOT NULL "
             "AND (local_path IS NULL OR local_path = '')",
    );

    if (rows.isEmpty) return;
    Log.i('[DownSync] Downloading ${rows.length} thumbnail(s)...');

    for (final row in rows) {
      final image = FarmImage.fromMap(row);
      try {
        final path = await ImageSyncService.instance.fetchAndRecache(image);
        if (path != null) {
          Log.i('[DownSync] Thumbnail cached: ${image.imageId}');
        }
      } catch (e) {
        Log.e('[DownSync] Thumbnail download failed ${image.imageId}: $e');
      }
    }
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  Future<_PullResult> _pullCollection(
      _CollectionConfig cfg, String userId) async {
    final cursor      = await LocalDb.instance.getLastSyncedAt(cfg.collection);
    final isFirstSync = cursor == null;

    Log.i('[DownSync] Pulling ${cfg.table} '
        '(cursor: ${cursor ?? 'first sync'})');

    final databases = AppwriteClient.instance.databases;
    int written   = 0;
    int conflicts = 0;
    int offset    = 0;

    while (true) {
      final queries = <String>[
        Query.equal('created_by', userId),
        Query.limit(_pageSize),
        Query.offset(offset),
        Query.orderAsc('created_at'),
      ];

      if (!isFirstSync) {
        queries.add(Query.greaterThan('created_at', cursor));
      }

      final result = await databases.listDocuments(
        databaseId:   AppwriteClient.kDatabaseId,
        collectionId: cfg.collection,
        queries:      queries,
      );

      Log.i('[DownSync] ${cfg.table}: Appwrite returned '
          '${result.documents.length} doc(s) at offset $offset');

      if (result.documents.isEmpty) break;

      final db = await LocalDb.instance.database;

      // Deduplicate within the page — Appwrite can return the same document
      // multiple times when offset-based pagination overlaps (known Appwrite bug).
      final seenInPage = <String>{};

      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        for (final doc in result.documents) {
          final incoming = _documentToRow(doc.data, cfg);

          final recordId = incoming[cfg.primaryKey]?.toString();
          if (recordId == null) {
            Log.w('[DownSync] Skipping ${cfg.table} doc — null primaryKey');
            continue;
          }

          // Client-side userId guard — belt-and-suspenders in case Appwrite
          // permissions ever return documents belonging to another user.
          final docUserId = incoming['created_by']?.toString();
          if (docUserId != null && docUserId != userId) {
            Log.w('[DownSync] Skipping ${cfg.table}/$recordId — '
                'belongs to $docUserId not $userId');
            continue;
          }

          // Skip duplicate within this page
          if (!seenInPage.add(recordId)) {
            Log.w('[DownSync] Duplicate doc $recordId in page — skipping');
            continue;
          }

          // Conflict check — record already exists locally with different data
          final existing = await db.query(
            cfg.table,
            where:     '${cfg.primaryKey} = ?',
            whereArgs: [recordId],
            limit:     1,
          );

          if (existing.isNotEmpty) {
            final localRow = Map<String, dynamic>.from(existing.first);
            if (_isDifferent(localRow, incoming)) {
              conflicts++;
              _recordConflict(
                table:     cfg.table,
                recordId:  recordId,
                localRow:  localRow,
                remoteRow: incoming,
                userId:    userId,
              ).catchError((e) {
                Log.e('[DownSync] Conflict record failed for $recordId: $e');
              });
              Log.w('[DownSync] Conflict on ${cfg.table}/$recordId — '
                  'Appwrite wins, conflict logged.');
            }
          }

          // Upsert — Appwrite always wins
          await db.insert(
            cfg.table,
            incoming,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          written++;
        }
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      Log.i('[DownSync] ${cfg.table}: wrote $written so far '
          '(page offset $offset, ${result.documents.length} fetched)');

      if (result.documents.length < _pageSize) break;
      offset += _pageSize;
    }

    return _PullResult(written: written, conflicts: conflicts);
  }

  // ── Conflict recording ──────────────────────────────────────────────────────

  Future<void> _recordConflict({
    required String table,
    required String recordId,
    required Map<String, dynamic> localRow,
    required Map<String, dynamic> remoteRow,
    required String userId,
  }) async {
    final now = DateTime.now().toUtc();

    final diffFields = <String, dynamic>{};
    final allKeys = {...localRow.keys, ...remoteRow.keys};
    for (final key in allKeys) {
      final lv = localRow[key];
      final rv = remoteRow[key];
      if (lv?.toString() != rv?.toString()) {
        diffFields[key] = jsonEncode({'local': lv, 'remote': rv});
      }
    }

    final conflictId = _uuid.v4();

    await AppwriteClient.instance.databases.createDocument(
      databaseId:   AppwriteClient.kDatabaseId,
      collectionId: AppwriteClient.colSyncConflicts,
      documentId:   conflictId,
      data: {
        'conflict_id': conflictId,
        'table_name':  table,
        'record_id':   recordId,
        'user_id':     userId,
        'resolution':  'appwrite_wins',
        'diff_json':   jsonEncode(diffFields),
        'local_json':  jsonEncode(localRow),
        'remote_json': jsonEncode(remoteRow),
        'conflict_at': now.toIso8601String(),
        'created_by':  userId,
        'created_at':  now.toIso8601String(),
      },
    );

    Log.i('[DownSync] Conflict recorded: $conflictId ($table/$recordId)');
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  bool _isDifferent(
      Map<String, dynamic> local, Map<String, dynamic> remote) {
    for (final key in remote.keys) {
      if (local[key]?.toString() != remote[key]?.toString()) return true;
    }
    return false;
  }

  // Fields whose values must be lowercased to satisfy local SQLite CHECK constraints.
  // Appwrite stores these as uppercase (MPESA, PAID, ACTIVE etc.) but local
  // schema uses lowercase to match Dart enum .name output.
  static const _lowercaseFields = {
    'type', 'status', 'category', 'unit', 'session',
    'payment_method', 'payment_status', 'transaction_type', 'method',
    'upload_status', 'entity_type',
  };

  Map<String, dynamic> _documentToRow(
      Map<String, dynamic> data, _CollectionConfig cfg) {
    final row = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      var   val = entry.value;

      if (key.startsWith('\$')) continue;  // Appwrite system fields

      if (key == 'is_kra_certified') {
        row[key] = (val == true) ? 1 : 0;
        continue;
      }

      // Normalise enum strings to lowercase so they pass SQLite CHECK constraints
      if (val is String && _lowercaseFields.contains(key)) {
        val = val.toLowerCase();
      }

      row[key] = val;
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
  const _CollectionConfig({
    required this.collection,
    required this.table,
    required this.primaryKey,
  });
}