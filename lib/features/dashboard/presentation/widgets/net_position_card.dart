// lib/features/dashboard/presentation/widgets/net_position_card.dart

import 'package:flutter/material.dart';
import '../../../../data/models/models.dart';

class NetPositionCard extends StatelessWidget {
  final DashboardSummary summary;
  const NetPositionCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final net = summary.netPosition;
    final isPositive = net >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4332),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Net Position',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w500)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isPositive ? const Color(0xFF52B788) : Colors.red.shade400,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Text(isPositive ? 'Profit' : 'Loss',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          _fmt(net.abs()),
          style: const TextStyle(
              color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1),
        ),
        const SizedBox(height: 16),
        Row(children: [
          _MiniStat('Sales', _fmt(summary.totalSalesAllTime), Icons.trending_up),
          Container(width: 1, height: 30, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 16)),
          _MiniStat('Purchases', _fmt(summary.totalPurchasesAllTime), Icons.trending_down),
          Container(width: 1, height: 30, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 16)),
          _MiniStat('Herd', '${summary.livestockCount + summary.cropCount} assets', Icons.pets),
        ]),
      ]),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return 'KES ${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return 'KES ${(v / 1000).toStringAsFixed(1)}k';
    return 'KES ${v.toStringAsFixed(0)}';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MiniStat(this.label, this.value, this.icon);
  
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 11, color: Colors.white54),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}