// lib/data/repositories/herd_repository.dart

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/local_db.dart';
import '../../services/session_manager.dart';
import '../../services/sync_service.dart';
import '../models/models.dart';

const _uuid = Uuid();

class HerdRepository {
  final LocalDb _db;
  HerdRepository({LocalDb? db}) : _db = db ?? LocalDb.instance;

  String get _uid => SessionManager.instance.currentUserId;

  Future<Asset> saveAsset(Asset asset) async {
    final db          = await _db.database;
    final ledgerEntry = LedgerEntry(
      eventId:   _uuid.v4(),
      type:      LedgerType.herdUpdate,
      sourceId:  asset.assetId,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    final stamped = asset.copyWith(
      lastEventId: ledgerEntry.eventId,
      createdBy:   _uid,
    );
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', ledgerEntry.toMap());
      await txn.insert('assets', stamped.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.addToQueue(txn, recordId: asset.assetId, tableName: 'assets');
    });
    SyncService().processQueue();
    return stamped;
  }

  Future<void> updateAsset(Asset asset) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'assets', asset.toMap(),
        where: 'asset_id = ?',
        whereArgs: [asset.assetId],
      );
      await _db.addToQueue(txn, recordId: asset.assetId, tableName: 'assets', operation: 'UPDATE');
    });
    SyncService().processQueue();
  }

  Future<AssetEvent> saveAssetEvent(AssetEvent event) async {
    final db      = await _db.database;
    final stamped = event.copyWith(createdBy: _uid);
    await db.transaction((txn) async {
      await txn.insert('asset_events', stamped.toMap());
      await _db.addToQueue(txn, recordId: event.eventId, tableName: 'asset_events');

      if (event.eventType == 'weightCheck' && event.metadata?['weight_kg'] != null) {
        await txn.execute(
          'UPDATE assets SET weight_kg = ? WHERE asset_id = ?',
          [event.metadata!['weight_kg'], event.assetId],
        );
      }

      if (event.eventType == 'sold' || event.eventType == 'deceased') {
        final newStatus = event.eventType == 'sold' ? 'sold' : 'deceased';
        await txn.execute(
          'UPDATE assets SET status = ? WHERE asset_id = ?',
          [newStatus, event.assetId],
        );
      }
    });
    SyncService().processQueue();
    return stamped;
  }

  Future<AssetEvent> updateAssetEvent(AssetEvent event) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'asset_events',
        event.toMap(),
        where: 'event_id = ?',
        whereArgs: [event.eventId],
      );
      await _db.addToQueue(txn, recordId:  event.eventId, tableName: 'asset_events', operation: 'UPDATE');
    });
    SyncService().processQueue();
    return event;
  }

  Future<MilkLog> saveMilkLog(MilkLog log) async {
    final db      = await _db.database;
    final stamped = log.copyWith(createdBy: _uid);
    await db.transaction((txn) async {
      await txn.insert('milk_logs', stamped.toMap());
      await _db.addToQueue(txn, recordId: log.logId, tableName: 'milk_logs');
    });
    SyncService().processQueue();
    return stamped;
  }

  Future<List<Asset>> getActiveAssets(AssetCategory category) async {
    final db   = await _db.database;
    final rows = await db.query(
      'assets',
      where: "category = ? AND status = 'active'",
      whereArgs: [category.name],
      orderBy: 'tag_name ASC',
    );
    return rows.map(Asset.fromMap).toList();
  }

  Future<List<AssetEvent>> getEventsForAsset(String assetId) async {
    final db   = await _db.database;
    final rows = await db.query(
      'asset_events',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      orderBy: 'recorded_at DESC',
    );
    return rows.map(AssetEvent.fromMap).toList();
  }

  Future<List<MilkLog>> getMilkLogs({required String assetId, DateTime? from, DateTime? to}) async {
    final db   = await _db.database;
    var where  = 'asset_id = ?';
    final args = <dynamic>[assetId];
    if (from != null) { where += ' AND recorded_at >= ?'; args.add(from.toIso8601String()); }
    if (to   != null) { where += ' AND recorded_at <= ?'; args.add(to.toIso8601String()); }
    final rows = await db.query(
      'milk_logs',
      where: where,
      whereArgs: args,
      orderBy: 'recorded_at DESC',
    );
    return rows.map(MilkLog.fromMap).toList();
  }

  Future<double> getTotalMilkForAsset(String assetId, {DateTime? from}) async {
    final db   = await _db.database;
    var where  = 'asset_id = ?';
    final args = <dynamic>[assetId];
    if (from != null) { where += ' AND recorded_at >= ?'; args.add(from.toIso8601String()); }
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(litres), 0.0) as total FROM milk_logs WHERE $where',
      args,
    );
    return (result.first['total'] as num).toDouble();
  }
}