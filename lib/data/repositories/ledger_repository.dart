import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/local_db.dart';
import '../../services/session_manager.dart';
import '../../services/sync_service.dart';
import '../models/ledger_entry.dart';

const _uuid = Uuid();

class LedgerRepository {
  final LocalDb _db;
  LedgerRepository({LocalDb? db}) : _db = db ?? LocalDb.instance;

  String get _uid => SessionManager.instance.currentUserId;

  // ── Record a Sale ──────────────────────────────────────────────────────────

  Future<LedgerEntry> recordSale({
    required String sourceId,
    required double amount,
    required Financial financial,
    Map<String, dynamic>? metadata,
  }) async {
    final entry = LedgerEntry(
      eventId:   _uuid.v4(),
      type:      LedgerType.sale,
      sourceId:  sourceId,
      amount:    amount,
      status:    LedgerStatus.pending,
      metadata:  metadata,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await txn.insert('financials',
          financial.copyWith(eventId: entry.eventId, createdBy: _uid).toMap());
      await _db.addToQueue(txn, recordId: entry.eventId,           tableName: 'ledger_entries');
      await _db.addToQueue(txn, recordId: financial.transactionId, tableName: 'financials');
    });
    SyncService().processQueue();
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
      eventId:   _uuid.v4(),
      type:      LedgerType.purchase,
      sourceId:  sourceId,
      amount:    amount,
      status:    LedgerStatus.pending,
      metadata:  metadata,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await txn.insert('financials',
          financial.copyWith(eventId: entry.eventId, createdBy: _uid).toMap());
      await _db.addToQueue(txn, recordId: entry.eventId,            tableName: 'ledger_entries');
      await _db.addToQueue(txn, recordId: financial.transactionId,  tableName: 'financials');
    });
    SyncService().processQueue();
    return entry;
  }

  // ── Add a Partial Payment ──────────────────────────────────────────────────
  /// Records one payment instalment against an existing sale.
  /// Updates financials.amount_paid and recalculates payment_status atomically.

  Future<PartialPayment> addPartialPayment({
    required String transactionId,
    required double amount,
    required PaymentMethod method,
    String? mpesaReceipt,
    String? checkoutRequestId,
    String? notes,
  }) async {
    final payment = PartialPayment(
      paymentId:          _uuid.v4(),
      transactionId:      transactionId,
      amount:             amount,
      method:             method,
      mpesaReceipt:       mpesaReceipt,
      checkoutRequestId:  checkoutRequestId,
      notes:              notes,
      createdBy:          _uid,
      createdAt:          DateTime.now(),
    );

    final db = await _db.database;

    await db.transaction((txn) async {
      // 1. Insert the payment record
      await txn.insert('partial_payments', payment.toMap());

      // 2. Increment amount_paid on the parent financial record
      await txn.rawUpdate('''
        UPDATE financials
        SET amount_paid = amount_paid + ?,
            payment_status = CASE
              WHEN (amount_paid + ?) >= amount THEN 'paid'
              ELSE 'pending'
            END
        WHERE transaction_id = ?
      ''', [amount, amount, transactionId]);

      // 3. Queue both for cloud sync
      await _db.addToQueue(txn,
          recordId: payment.paymentId,
          tableName: 'partial_payments');
      await _db.addToQueue(txn,
          recordId: transactionId,
          tableName: 'financials',
          operation: 'UPDATE');
    });

    SyncService().processQueue();
    return payment;
  }

  // ── Get Partial Payments for a Transaction ─────────────────────────────────

  Future<List<PartialPayment>> getPaymentsForTransaction(
      String transactionId) async {
    final db   = await _db.database;
    final rows = await db.query(
      'partial_payments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PartialPayment.fromMap).toList();
  }

  // ── Get Outstanding Sales (partial or fully unpaid) ────────────────────────

  Future<List<Financial>> getOutstandingSales() async {
    final db   = await _db.database;
    final rows = await db.query(
      'financials',
      where: "transaction_type = 'sale' AND payment_status = 'pending' AND created_by = ?",
      whereArgs: [_uid],
      orderBy: 'created_at DESC',
    );
    return rows.map(Financial.fromMap).toList();
  }

  // ── Save Asset ─────────────────────────────────────────────────────────────

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
      await txn.insert('assets', stamped.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.addToQueue(txn, recordId: asset.assetId, tableName: 'assets');
    });
    return stamped;
  }

  // ── Update Asset ───────────────────────────────────────────────────────────

  Future<void> updateAsset(Asset asset) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'assets', asset.toMap(),
        where: 'asset_id = ?',
        whereArgs: [asset.assetId],
      );
      await _db.addToQueue(txn,
          recordId: asset.assetId, tableName: 'assets', operation: 'UPDATE');
    });
  }

  // ── Adjust Inventory ───────────────────────────────────────────────────────

  Future<InventoryItem> adjustInventory({
    required InventoryItem item,
    required double delta,
  }) async {
    final db      = await _db.database;
    final updated = item.copyWith(
        quantity: (item.quantity + delta).clamp(0, double.infinity));
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
      await txn.insert('inventory', updated.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.addToQueue(txn, recordId: item.itemId, tableName: 'inventory');
    });
    return updated;
  }

  // ── Add Inventory Item ─────────────────────────────────────────────────────

  Future<InventoryItem> addInventoryItem(InventoryItem item) async {
    final db      = await _db.database;
    final stamped = item.copyWith(createdBy: _uid);
    await db.transaction((txn) async {
      await txn.insert('inventory', stamped.toMap());
      await _db.addToQueue(txn, recordId: item.itemId, tableName: 'inventory');
    });
    return stamped;
  }

  // ── Asset Events ───────────────────────────────────────────────────────────

  Future<AssetEvent> saveAssetEvent(AssetEvent event) async {
    final db      = await _db.database;
    final stamped = event.copyWith(createdBy: _uid);
    await db.transaction((txn) async {
      await txn.insert('asset_events', stamped.toMap());
      await _db.addToQueue(txn, recordId: event.eventId, tableName: 'asset_events');

      if (event.eventType == 'weightCheck' &&
          event.metadata?['weight_kg'] != null) {
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
    return stamped;
  }

  // ── Milk Logs ──────────────────────────────────────────────────────────────

  Future<MilkLog> saveMilkLog(MilkLog log) async {
    final db      = await _db.database;
    final stamped = log.copyWith(createdBy: _uid);
    await db.transaction((txn) async {
      await txn.insert('milk_logs', stamped.toMap());
      await _db.addToQueue(txn, recordId: log.logId, tableName: 'milk_logs');
    });
    return stamped;
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  Future<List<LedgerEntry>> getRecentLedger({int limit = 50}) async {
    final db   = await _db.database;
    final rows = await db.query(
      'ledger_entries',
      where: 'created_by = ?',
      whereArgs: [_uid],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(LedgerEntry.fromMap).toList();
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

  Future<List<InventoryItem>> getAllInventory() async {
    final db   = await _db.database;
    final rows = await db.query(
      'inventory',
      orderBy: 'category ASC, item_name ASC',
    );
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<List<InventoryItem>> getLowStockItems() async {
    final db   = await _db.database;
    final rows = await db.rawQuery(
      'SELECT * FROM inventory WHERE quantity <= reorder_level ORDER BY item_name',
    );
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<List<Financial>> getRecentFinancials({int limit = 50}) async {
    final db   = await _db.database;
    final rows = await db.query(
      'financials',
      where: 'created_by = ?',
      whereArgs: [_uid],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Financial.fromMap).toList();
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

  Future<List<MilkLog>> getMilkLogs({
    required String assetId,
    DateTime? from,
    DateTime? to,
  }) async {
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

  // ── Dashboard Summary ──────────────────────────────────────────────────────

  Future<DashboardSummary> getDashboardSummary() async {
    final db = await _db.database;

    final salesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) as total FROM financials "
      "WHERE transaction_type = 'sale' AND created_by = ?", [_uid],
    );
    final totalSales = (salesResult.first['total'] as num).toDouble();

    final purchasesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) as total FROM financials "
      "WHERE transaction_type = 'purchase' AND created_by = ?", [_uid],
    );
    final totalPurchases = (purchasesResult.first['total'] as num).toDouble();

    final now        = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final salesMonthResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) as total FROM financials "
      "WHERE transaction_type = 'sale' AND created_at >= ? AND created_by = ?",
      [monthStart, _uid],
    );
    final totalSalesThisMonth = (salesMonthResult.first['total'] as num).toDouble();

    // Outstanding: sum of (amount - amount_paid) for pending sales
    final outstandingResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount - amount_paid), 0.0) as total FROM financials "
      "WHERE transaction_type = 'sale' AND payment_status = 'pending' AND created_by = ?",
      [_uid],
    );
    final totalOutstanding = (outstandingResult.first['total'] as num).toDouble();

    final livestockResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM assets "
      "WHERE category = 'livestock' AND status = 'active'",
    );
    final livestockCount = livestockResult.first['count'] as int;

    final cropResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM assets "
      "WHERE category = 'crop' AND status = 'active'",
    );
    final cropCount = cropResult.first['count'] as int;

    final lowStockResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM inventory WHERE quantity <= reorder_level',
    );
    final lowStockCount = lowStockResult.first['count'] as int;

    final syncResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'pending'",
    );
    final pendingSyncCount = syncResult.first['count'] as int;

    final recentRows = await db.query(
      'financials',
      where: 'created_by = ?',
      whereArgs: [_uid],
      orderBy: 'created_at DESC',
      limit: 10,
    );
    final recentTransactions = recentRows.map(Financial.fromMap).toList();

    return DashboardSummary(
      totalSalesAllTime:     totalSales,
      totalPurchasesAllTime: totalPurchases,
      totalSalesThisMonth:   totalSalesThisMonth,
      totalOutstanding:      totalOutstanding,
      livestockCount:        livestockCount,
      cropCount:             cropCount,
      lowStockCount:         lowStockCount,
      pendingSyncCount:      pendingSyncCount,
      recentTransactions:    recentTransactions,
    );
  }
}