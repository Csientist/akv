import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/local_db.dart';
import '../models/ledger_entry.dart'; // Make sure this file contains Asset, InventoryItem, and Financial too
import '../../services/sync_service.dart';

const _uuid = Uuid();

class LedgerRepository {
  final LocalDb _db;
  final SyncService _sync;

  LedgerRepository({LocalDb? db, SyncService? sync}) 
      : _db = db ?? LocalDb.instance,
        _sync = sync ?? SyncService();

  // ── Record a Sale ──────────────────────────────────────────────────────────
  Future<LedgerEntry> recordSale({
    required String sourceId,
    required double amount,
    required Financial financial,
    Map<String, dynamic>? metadata,
  }) async {
    final entry = LedgerEntry(
      eventId: _uuid.v4(),
      type: LedgerType.SALE, // Fixed enum casing
      sourceId: sourceId,
      amount: amount,
      status: LedgerStatus.pending,
      metadata: metadata,
      createdAt: DateTime.now().toUtc(), // Passed as DateTime, model handles String conversion
    );

    final database = await _db.database;

    await database.transaction((txn) async {
      // 1. Write the Ledger Entry
      await txn.insert('ledger_entries', entry.toMap());
      // 2. Write the Financial record
      await txn.insert('financials', financial.toMap());
      
      // 3. Queue BOTH for Sync
      await _db.addToQueue(txn, recordId: entry.eventId, tableName: 'ledger_entries');
      await _db.addToQueue(txn, recordId: financial.transactionId, tableName: 'financials');
    });

    _sync.processQueue(); // Trigger background sync
    return entry;
  }

  // ── Record a Purchase ──────────────────────────────────────────────────────
  Future<LedgerEntry> recordPurchase({
    required String sourceId,
    required double amount,
    required Financial financial,
    Map<String, dynamic>? metadata,
  }) async {
    final entry = LedgerEntry(
      eventId: _uuid.v4(),
      type: LedgerType.PURCHASE, // Fixed enum casing
      sourceId: sourceId,
      amount: amount,
      metadata: metadata,
      createdAt: DateTime.now().toUtc(),
    );

    final database = await _db.database;
    await database.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await txn.insert('financials', financial.toMap());
      
      // Queue both records
      await _db.addToQueue(txn, recordId: entry.eventId, tableName: 'ledger_entries');
      await _db.addToQueue(txn, recordId: financial.transactionId, tableName: 'financials');
    });

    _sync.processQueue();
    return entry;
  }

  // ── Save/Update an Asset (Herd or Crop) ────────────────────────────────────
  Future<Asset> saveAsset(Asset asset) async {
    final database = await _db.database;
    
    // Create audit log for the asset change
    final ledgerEntry = LedgerEntry(
      eventId: _uuid.v4(),
      type: LedgerType.HERD_UPDATE, // Fixed enum casing
      sourceId: asset.assetId,
      createdAt: DateTime.now().toUtc(),
    );

    final updatedAsset = Asset(
      assetId: asset.assetId,
      category: asset.category,
      breedType: asset.breedType,
      status: asset.status,
      lastEventId: ledgerEntry.eventId,
      createdAt: asset.createdAt, // Removed ?? _now (createdAt is non-nullable)
    );

    await database.transaction((txn) async {
      // Write Ledger Log
      await txn.insert('ledger_entries', ledgerEntry.toMap());
      // Upsert Asset
      await txn.insert(
        'assets',
        updatedAsset.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // Sync both the Cow/Crop and the Log entry
      await _db.addToQueue(txn, recordId: ledgerEntry.eventId, tableName: 'ledger_entries');
      await _db.addToQueue(txn, recordId: updatedAsset.assetId, tableName: 'assets');
    });

    _sync.processQueue();
    return updatedAsset;
  }

  // ── Adjust Inventory (Consumption or Restock) ──────────────────────────────
  Future<InventoryItem> adjustInventory({
    required InventoryItem item,
    required double delta, 
  }) async {
    final database = await _db.database;

    final updated = InventoryItem(
      itemId: item.itemId,
      itemName: item.itemName,
      quantity: (item.quantity + delta).clamp(0, double.infinity),
      unit: item.unit,
      reorderLevel: item.reorderLevel,
      createdAt: item.createdAt, // Removed ?? _now
    );

    final ledgerEntry = LedgerEntry(
      eventId: _uuid.v4(),
      type: LedgerType.INVENTORY_ADJUST, // Fixed enum casing
      sourceId: item.itemId,
      amount: delta,
      createdAt: DateTime.now().toUtc(),
    );

    await database.transaction((txn) async {
      await txn.insert('ledger_entries', ledgerEntry.toMap());
      await txn.insert(
        'inventory',
        updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // Sync the new quantity and the adjustment log
      await _db.addToQueue(txn, recordId: ledgerEntry.eventId, tableName: 'ledger_entries');
      await _db.addToQueue(txn, recordId: updated.itemId, tableName: 'inventory');
    });

    _sync.processQueue();
    return updated;
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  Future<List<LedgerEntry>> getRecentLedger({int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      'ledger_entries',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(LedgerEntry.fromMap).toList();
  }

  Future<List<Asset>> getActiveAssets(AssetCategory category) async {
    final db = await _db.database;
    final rows = await db.query(
      'assets',
      where: "category = ? AND status != 'SOLD' AND status != 'DECEASED'",
      whereArgs: [category.name],
    );
    return rows.map(Asset.fromMap).toList();
  }

  Future<List<InventoryItem>> getLowStockItems() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT * FROM inventory WHERE quantity <= reorder_level ORDER BY item_name',
    );
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<List<Financial>> getUncertifiedTransactions() async {
    final db = await _db.database;
    final rows = await db.query(
      'financials',
      where: 'is_kra_certified = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(Financial.fromMap).toList();
  }
}