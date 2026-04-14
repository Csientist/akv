// lib/data/models/monthly_summary.dart

class MonthlySummary {
  final int flockSize;
  final int birthsThisMonth;
  final int deathsThisMonth;
  final double totalIncome;
  final double totalExpenses;

  const MonthlySummary({
    required this.flockSize,
    required this.birthsThisMonth,
    required this.deathsThisMonth,
    required this.totalIncome,
    required this.totalExpenses,
  });

  double get netProfit => totalIncome - totalExpenses;
}