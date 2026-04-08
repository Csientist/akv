// lib/features/dashboard/presentation/widgets/recent_activity_list.dart

import 'package:flutter/material.dart';
import '../../../../data/models/models.dart';
import '../../../../shared/widgets/shared_widgets.dart';

class RecentActivityList extends StatelessWidget {
  final DashboardSummary summary;
  const RecentActivityList({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SectionLabel('Recent Activity'),
            const Spacer(),
            if (summary.recentTransactions.isNotEmpty)
              Text(
                '${summary.recentTransactions.length} transactions',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500),
              ),
          ]
        ),
        const SizedBox(height: 12),
        if (summary.recentTransactions.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD8E8E0)),
            ),
            child: const EmptyStateView(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              subtitle: 'Record a sale or purchase to see activity here',
            ),
          )
        else
          ...summary.recentTransactions.map((t) => _ActivityTile(txn: t)),

        if (summary.recentTransactions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD8E8E0)),
            ),
            child: Row(children: [
              _FooterStat('All-time Sales', _fmt(summary.totalSalesAllTime), const Color(0xFF2D6A4F)),
              Container(width: 1, height: 28, color: const Color(0xFFD8E8E0), margin: const EdgeInsets.symmetric(horizontal: 16)),
              _FooterStat('All-time Purchases', _fmt(summary.totalPurchasesAllTime), const Color(0xFF9B2226)),
            ]),
          ),
        ],
      ],
    );
  }

  String _fmt(double amount) {
    if (amount >= 1000000) return 'KES ${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000)    return 'KES ${(amount / 1000).toStringAsFixed(1)}k';
    return 'KES ${amount.toStringAsFixed(0)}';
  }
}

class _ActivityTile extends StatelessWidget {
  final Financial txn;
  const _ActivityTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isSale = txn.transactionType == TransactionType.sale;
    final color = isSale ? const Color(0xFF2D6A4F) : const Color(0xFF9B2226);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(isSale ? Icons.trending_up : Icons.trending_down,
                color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(txn.customerSupplierName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  txn.description?.isNotEmpty == true ? txn.description! : txn.paymentMethod.name.toUpperCase(),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ]
            )
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end, 
            children: [
              Text('${isSale ? '+' : '-'}KES ${txn.amount.toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color)),
              Text(_relativeDate(txn.createdAt),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            ]
          ),
        ]
      ),
    );
  }

  String _relativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _FooterStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _FooterStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ]
        ),
      );
}