// lib/data/models/dashboard_summary.dart

import 'financial.dart';

class DashboardSummary {
  final double totalSalesAllTime;
  final double totalPurchasesAllTime;
  final double totalSalesThisMonth;
  final double totalOutstanding;
  final int    livestockCount;
  final int    cropCount;
  final int    lowStockCount;
  final int    pendingSyncCount;
  final List<Financial> recentTransactions;

  const DashboardSummary({
    required this.totalSalesAllTime,
    required this.totalPurchasesAllTime,
    required this.totalSalesThisMonth,
    this.totalOutstanding = 0.0,
    required this.livestockCount,
    required this.cropCount,
    required this.lowStockCount,
    required this.pendingSyncCount,
    required this.recentTransactions,
  });

  double get netPosition => totalSalesAllTime - totalPurchasesAllTime;
}