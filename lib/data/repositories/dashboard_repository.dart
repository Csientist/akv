// lib/data/repositories/dashboard_repository.dart

import '../../core/local_db.dart';
import '../../services/session_manager.dart';
import '../models/models.dart';

class DashboardRepository {
  final LocalDb _db;
  DashboardRepository({LocalDb? db}) : _db = db ?? LocalDb.instance;

  String get _uid => SessionManager.instance.currentUserId;

  Future<DashboardSummary> getDashboardSummary() async {
    final db = await _db.database;

    final salesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) as total FROM financials WHERE transaction_type = 'sale' AND created_by = ?", [_uid],
    );
    final totalSales = (salesResult.first['total'] as num).toDouble();

    final purchasesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) as total FROM financials WHERE transaction_type = 'purchase' AND created_by = ?", [_uid],
    );
    final totalPurchases = (purchasesResult.first['total'] as num).toDouble();

    final now        = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final salesMonthResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) as total FROM financials WHERE transaction_type = 'sale' AND created_at >= ? AND created_by = ?",
      [monthStart, _uid],
    );
    final totalSalesThisMonth = (salesMonthResult.first['total'] as num).toDouble();

    final outstandingResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount - amount_paid), 0.0) as total FROM financials WHERE transaction_type = 'sale' AND payment_status = 'pending' AND created_by = ?",
      [_uid],
    );
    final totalOutstanding = (outstandingResult.first['total'] as num).toDouble();

    final livestockResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM assets WHERE category = 'livestock' AND status = 'active' AND created_by = ?", [_uid]
    );
    final livestockCount = livestockResult.first['count'] as int;

    final cropResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM assets WHERE category = 'crop' AND status = 'active' AND created_by = ?", [_uid]
    );
    final cropCount = cropResult.first['count'] as int;

    final lowStockResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM inventory WHERE quantity <= reorder_level AND created_by = ?', [_uid]
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

  Future<MonthlySummary> getMonthlySummary() async {
    final db = await _db.database;
    
    final flockCount = await db.rawQuery('''
      SELECT COUNT(*) as count FROM assets 
      WHERE status = 'active' AND category = 'livestock' AND created_by = ?
    ''', [_uid]);

    final births = await db.rawQuery('''
      SELECT COUNT(*) as count FROM asset_events 
      WHERE event_type = 'birth' AND created_by = ?
        AND strftime('%Y-%m', recorded_at) = strftime('%Y-%m', 'now')
    ''', [_uid]);

    final deaths = await db.rawQuery('''
      SELECT COUNT(*) as count FROM asset_events 
      WHERE (event_type = 'deceased' OR event_type = 'cropLoss') AND created_by = ?
        AND strftime('%Y-%m', recorded_at) = strftime('%Y-%m', 'now')
    ''', [_uid]);

    final income = await db.rawQuery('''
      SELECT SUM(amount) as total FROM financials 
      WHERE transaction_type = 'sale' AND payment_status != 'failed' AND created_by = ?
        AND strftime('%Y-%m', created_at) = strftime('%Y-%m', 'now')
    ''', [_uid]);

    final expenses = await db.rawQuery('''
      SELECT SUM(amount) as total FROM financials 
      WHERE transaction_type = 'purchase' AND payment_status != 'failed' AND created_by = ?
        AND strftime('%Y-%m', created_at) = strftime('%Y-%m', 'now')
    ''', [_uid]);
    
    final feedCosts = await db.rawQuery('''
      SELECT SUM(feed_cost) as total FROM flock_logs 
      WHERE created_by = ?
        AND strftime('%Y-%m', recorded_at) = strftime('%Y-%m', 'now')
    ''', [_uid]);

    final baseExpenses = (expenses.first['total'] as num?)?.toDouble() ?? 0.0;
    final extraFeedCosts = (feedCosts.first['total'] as num?)?.toDouble() ?? 0.0;

    return MonthlySummary(
      flockSize: flockCount.first['count'] as int? ?? 0,
      birthsThisMonth: births.first['count'] as int? ?? 0,
      deathsThisMonth: deaths.first['count'] as int? ?? 0,
      totalIncome: (income.first['total'] as num?)?.toDouble() ?? 0.0,
      totalExpenses: baseExpenses + extraFeedCosts,
    );
  }
}