// lib/features/herd/presentation/widgets/summary_banner.dart

import 'package:flutter/material.dart';
import '../../../../data/models/models.dart';

class SummaryBanner extends StatelessWidget {
  final List<Asset> assets;
  final AssetCategory category;

  const SummaryBanner({super.key, required this.assets, required this.category});

  @override
  Widget build(BuildContext context) {
    final total = assets.length;
    final healthy = assets.where((a) => a.healthNotes == null || a.healthNotes!.isEmpty).length;
    final attention = total - healthy;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4332), 
        borderRadius: BorderRadius.circular(20)
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround, 
        children: [
          _Stat('$total', category == AssetCategory.livestock ? 'Total Head' : 'Total Plots'),
          _Stat('$healthy', 'Healthy'),
          _Stat('$attention', 'Attention', highlight: attention > 0),
        ]
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;

  const _Stat(this.value, this.label, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value, 
          style: TextStyle(
            color: highlight ? Colors.orangeAccent : Colors.white, 
            fontSize: 24, 
            fontWeight: FontWeight.bold
          )
        ),
        Text(
          label, 
          style: const TextStyle(color: Colors.white70, fontSize: 12)
        ),
      ]
    );
  }
}