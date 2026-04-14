// lib/shared/widgets/asset_thumbnail.dart

import 'package:flutter/material.dart';
import '../../services/image_service.dart';
import '../../services/asset_image_widget.dart';

class AssetThumbnail extends StatelessWidget {
  final String assetId;
  final String tagName;
  final double size;

  const AssetThumbnail({
    super.key,
    required this.assetId,
    required this.tagName,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FarmImage>>(
      future: ImageService.instance.getImages(
        entityType: ImageEntityType.asset,
        entityId:   assetId,
      ),
      builder: (context, snap) {
        final first = snap.data?.isNotEmpty == true ? snap.data!.first : null;
        if (first != null) {
          return AssetImageWidget(
            image:        first,
            size:         size,
            borderRadius: BorderRadius.circular(size * 0.28),
          );
        }
        
        // Fallback — letter avatar
        return Container(
          width:  size,
          height: size,
          decoration: BoxDecoration(
            color:        const Color(0xFFD8F3DC),
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Center(
            child: Text(
              tagName.isNotEmpty ? tagName[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize:   size * 0.40,
                fontWeight: FontWeight.bold,
                color:      const Color(0xFF2D6A4F),
              ),
            ),
          ),
        );
      },
    );
  }
}