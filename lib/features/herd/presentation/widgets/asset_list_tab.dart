// lib/features/herd/presentation/widgets/asset_list_tab.dart

import 'package:flutter/material.dart';
import '../../../../data/models/models.dart';
import '../../../../data/repositories/repositories.dart';
import '../../../../shared/widgets/shared_widgets.dart';
import 'summary_banner.dart';
import 'animal_card.dart';

class AssetListTab extends StatelessWidget {
  final Future<List<Asset>> future;
  final AssetCategory category;
  final VoidCallback onRefresh;
  final HerdRepository repo;

  const AssetListTab({
    super.key, 
    required this.future, 
    required this.category, 
    required this.onRefresh, 
    required this.repo
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Asset>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)));
        }
        
        final assets = snap.data ?? [];
        
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            SummaryBanner(assets: assets, category: category),
            const SizedBox(height: 20),
            const SectionLabel('Animals'),
            const SizedBox(height: 10),
            if (assets.isEmpty)
              EmptyStateView(
                icon: category == AssetCategory.livestock ? Icons.pets : Icons.grass,
                title: 'No ${category == AssetCategory.livestock ? 'livestock' : 'crops'} registered',
                subtitle: 'Tap Register to add one',
              )
            else
              ...assets.map((a) => AnimalCard(asset: a, onRefresh: onRefresh, repo: repo)),
          ],
        );
      },
    );
  }
}