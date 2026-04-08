// lib/features/dashboard/presentation/widgets/monthly_summary_card.dart

import 'package:flutter/material.dart';
import '../../../../data/models/models.dart';

class MonthlySummaryCard extends StatelessWidget {
  final MonthlySummary summary;
  const MonthlySummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final netProfit = summary.netProfit;
    final isProfit = netProfit >= 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E8E0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MonthlyMetric(icon: Icons.pets, label: 'Closing Flock', value: '${summary.flockSize}', color: const Color(0xFF2D6A4F)),
                _MonthlyMetric(icon: Icons.child_care, label: 'Births', value: '+${summary.birthsThisMonth}', color: Colors.blue.shade700),
                _MonthlyMetric(icon: Icons.warning_amber_rounded, label: 'Deaths', value: '-${summary.deathsThisMonth}', color: Colors.red.shade700),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _FinRow('Total Income', summary.totalIncome, Colors.green.shade700, Icons.arrow_downward),
                const SizedBox(height: 8),
                _FinRow('Total Expenses (Inc. Feed)', summary.totalExpenses, Colors.red.shade700, Icons.arrow_upward),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFE5E7EB)),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Net Profit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(
                      'KES ${netProfit.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isProfit ? const Color(0xFF2D6A4F) : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MonthlyMetric({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color.withValues(alpha: 0.7)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _FinRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _FinRow(this.label, this.amount, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text('KES ${amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
      ],
    );
  }
}