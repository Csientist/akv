// lib/features/herd/presentation/widgets/animal_card.dart

import 'package:flutter/material.dart';
import '../../../../data/models/models.dart';
import '../../../../data/repositories/repositories.dart';
import '../../../../shared/widgets/shared_widgets.dart';
import '../sheets/animal_detail_sheet.dart';
import '../sheets/add_asset_sheet.dart';

class AnimalCard extends StatelessWidget {
  final Asset asset;
  final VoidCallback onRefresh;
  final HerdRepository repo;

  const AnimalCard({
    super.key, 
    required this.asset, 
    required this.onRefresh, 
    required this.repo
  });

  @override
  Widget build(BuildContext context) {
    final hasHealth = asset.healthNotes != null && asset.healthNotes!.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hasHealth ? Colors.orange.shade200 : const Color(0xFFD8E8E0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AssetThumbnail(assetId: asset.assetId, tagName: asset.tagName, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Row(
                      children: [
                        Text(asset.tagName.isNotEmpty ? asset.tagName : 'Unnamed',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFD8F3DC), borderRadius: BorderRadius.circular(6)),
                          child: Text(asset.breedType, style: const TextStyle(fontSize: 10, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w600)),
                        ),
                      ]
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (asset.dateOfBirth != null) ...[
                          Icon(Icons.cake_outlined, size: 12, color: scheme.outline),
                          const SizedBox(width: 3),
                          Text(asset.displayAge, style: TextStyle(fontSize: 11, color: scheme.outline)),
                          const SizedBox(width: 10),
                        ],
                        if (asset.weightKg != null) ...[
                          Icon(Icons.monitor_weight_outlined, size: 12, color: scheme.outline),
                          const SizedBox(width: 3),
                          Text('${asset.weightKg!.toStringAsFixed(0)} kg', style: TextStyle(fontSize: 11, color: scheme.outline)),
                        ],
                      ]
                    ),
                    if (hasHealth) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange),
                          const SizedBox(width: 4),
                          Expanded(child: Text(asset.healthNotes!, style: const TextStyle(fontSize: 11, color: Colors.orange), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]
                      ),
                    ],
                  ]
                )
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: const Color(0xFF52796F),
                tooltip: 'Edit',
                onPressed: () => _openEdit(context),
              ),
            ]
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnimalDetailSheet(asset: asset, repo: repo, onRefresh: onRefresh),
    );
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddAssetSheet(
        existing: asset,
        onSaved: (updated) async {
          await repo.updateAsset(updated);
          onRefresh();
        },
      ),
    );
  }
}