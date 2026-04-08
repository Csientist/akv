// lib/data/repositories/flock_repository.dart

import 'package:sqflite/sqflite.dart';
import '../../core/local_db.dart';
import '../../services/session_manager.dart';
import '../../services/sync_service.dart';
import '../models/models.dart';

class FlockRepository {
  final LocalDb _db;
  FlockRepository({LocalDb? db}) : _db = db ?? LocalDb.instance;

  String get _uid => SessionManager.instance.currentUserId;

  Future<FlockLog> saveFlockLog(FlockLog log) async {
    final db = await _db.database;
    final stamped = log.copyWith(createdBy: _uid);
    
    await db.transaction((txn) async {
      await txn.insert('flock_logs', stamped.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.addToQueue(txn, recordId: stamped.logId, tableName: 'flock_logs');
    });
    
    SyncService().processQueue();
    return stamped;
  }

  Future<List<FlockLog>> getFlockLogs({int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      'flock_logs',
      where: 'created_by = ?',
      whereArgs: [_uid],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return rows.map(FlockLog.fromMap).toList();
  }
}