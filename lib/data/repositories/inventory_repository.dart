// lib/data/repositories/inventory_repository.dart

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/local_db.dart';
import '../../services/session_manager.dart';
import '../../services/sync_service.dart';
import '../models/models.dart';

const _uuid = Uuid();

class InventoryRepository {
  final LocalDb _db;
  InventoryRepository({LocalDb? db}) : _db = db ?? LocalDb.instance;

  String get _uid => SessionManager.instance.currentUserId;

  Future<InventoryItem> adjustInventory({required InventoryItem item, required double delta}) async {
    final db      = await _db.database;
    final updated = item.copyWith(quantity: (item.quantity + delta).clamp(0, double.infinity));
    final ledgerEntry = LedgerEntry(
      eventId:   _uuid.v4(),
      type:      LedgerType.inventoryAdjust,
      sourceId:  item.itemId,
      amount:    delta,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', ledgerEntry.toMap());
      await txn.insert('inventory', updated.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.addToQueue(txn, recordId: item.itemId, tableName: 'inventory');
    });
    SyncService().processQueue();
    return updated;
  }

  Future<InventoryItem> addInventoryItem(InventoryItem item) async {
    final db      = await _db.database;
    final stamped = item.copyWith(createdBy: _uid);
    await db.transaction((txn) async {
      await txn.insert('inventory', stamped.toMap());
      await _db.addToQueue(txn, recordId: item.itemId, tableName: 'inventory');
    });
    SyncService().processQueue();
    return stamped;
  }

  Future<InventoryItem> updateInventoryItem(InventoryItem item) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'inventory',
        item.toMap(),
        where: 'item_id = ?',
        whereArgs: [item.itemId],
      );
      await _db.addToQueue(txn, recordId: item.itemId, tableName: 'inventory', operation: 'UPDATE');
    });
    SyncService().processQueue();
    return item;
  }

  Future<List<InventoryItem>> getAllInventory() async {
    final db   = await _db.database;
    final rows = await db.query(
      'inventory',
      where: 'created_by = ?',
      whereArgs: [_uid],
      orderBy: 'category ASC, item_name ASC',
    );
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<List<InventoryItem>> getLowStockItems() async {
    final db   = await _db.database;
    final rows = await db.rawQuery(
      'SELECT * FROM inventory WHERE quantity <= reorder_level AND created_by = ? ORDER BY item_name',
      [_uid]
    );
    return rows.map(InventoryItem.fromMap).toList();
  }
}