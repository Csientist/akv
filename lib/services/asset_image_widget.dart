import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_service.dart';
import '../services/image_sync_service.dart';
import 'package:image_picker/image_picker.dart';


/// Displays an [FarmImage] with a three-tier fallback:
///   1. Local cache file (instant, offline)
///   2. Appwrite preview URL (online, fetches & re-caches)
///   3. Placeholder icon
///
/// Usage:
///   AssetImageWidget(image: image, size: 80)
///   AssetImageWidget.placeholder(size: 80, entityType: ImageEntityType.asset)
class AssetImageWidget extends StatefulWidget {
  final FarmImage? image;
  final double      size;
  final BoxFit      fit;
  final BorderRadius? borderRadius;

  const AssetImageWidget({
    super.key,
    required this.image,
    this.size          = 56,
    this.fit           = BoxFit.cover,
    this.borderRadius,
  });

  /// Convenience constructor for empty slots.
  const AssetImageWidget.placeholder({
    super.key,
    this.size         = 56,
    this.borderRadius,
  })  : image       = null,
        fit         = BoxFit.cover;

  @override
  State<AssetImageWidget> createState() => _AssetImageWidgetState();
}

class _AssetImageWidgetState extends State<AssetImageWidget> {
  String? _resolvedPath;
  bool    _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(AssetImageWidget old) {
    super.didUpdateWidget(old);
    if (old.image?.imageId != widget.image?.imageId ||
        old.image?.localPath != widget.image?.localPath) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final img = widget.image;
    if (img == null) return;

    // Tier 1 — local cache
    if (img.localPath != null && File(img.localPath!).existsSync()) {
      if (mounted) setState(() => _resolvedPath = img.localPath);
      return;
    }

    // Tier 2 — fetch from Appwrite, then cache
    if (img.appwriteFileId != null && !_loading) {
      setState(() => _loading = true);
      final path = await ImageSyncService.instance.fetchAndRecache(img);
      if (mounted) setState(() { _resolvedPath = path; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(10);
    final size   = widget.size;

    Widget content;

    if (_loading) {
      content = Container(
        color: const Color(0xFFE8F5EC),
        child: const Center(
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF52B788),
            ),
          ),
        ),
      );
    } else if (_resolvedPath != null) {
      content = Image.file(
        File(_resolvedPath!),
        fit:          widget.fit,
        width:        size,
        height:       size,
        errorBuilder: (_, _, _) => _Placeholder(size: size),
      );
    } else {
      content = _Placeholder(size: size);
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(width: size, height: size, child: content),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final double size;
  const _Placeholder({required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        color: const Color(0xFFEAF4EC),
        child: Icon(
          Icons.photo_camera_outlined,
          size:  size * 0.35,
          color: const Color(0xFF74C69D),
        ),
      );
}

// ── Image picker strip ────────────────────────────────────────────────────────

/// A horizontal row of image slots (up to [maxImages]).
/// Shows existing images + an "Add" button if slots remain.
///
/// Usage in herd detail:
///   AssetImageStrip(
///     images:    _images,
///     maxImages: 3,
///     onAdd:     (source) => _pickImage(source),
///     onDelete:  (img)    => _deleteImage(img),
///   )
class AssetImageStrip extends StatelessWidget {
  final List<FarmImage> images;
  final int              maxImages;
  final void Function(ImageSource source) onAdd;
  final void Function(FarmImage img)     onDelete;
  final double                            imageSize;

  const AssetImageStrip({
    super.key,
    required this.images,
    required this.maxImages,
    required this.onAdd,
    required this.onDelete,
    this.imageSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    final canAdd = images.length < maxImages;

    return SizedBox(
      height: imageSize,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...images.map((img) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onLongPress: () => _confirmDelete(context, img),
                  child: Stack(
                    children: [
                      AssetImageWidget(
                        image:        img,
                        size:         imageSize,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      // Pending upload indicator
                      if (!img.isUploaded)
                        Positioned(
                          top: 4, right: 4,
                          child: Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color:  const Color(0xFFD97706),
                              shape:  BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )),
          if (canAdd)
            GestureDetector(
              onTap: () => _showSourcePicker(context),
              child: Container(
                width:        imageSize,
                height:       imageSize,
                decoration:   BoxDecoration(
                  color:        const Color(0xFFEAF4EC),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(
                    color: const Color(0xFF74C69D),
                    width: 1.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: Color(0xFF40916C), size: 22),
                    SizedBox(height: 3),
                    Text('Add', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF40916C))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSourcePicker(BuildContext context) {
    showModalBottomSheet(
      context:  context,
      builder:  (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:  const Icon(Icons.camera_alt_outlined),
              title:    const Text('Take photo'),
              onTap: () {
                Navigator.pop(context);
                onAdd(ImageSource.camera);
              },
            ),
            ListTile(
              leading:  const Icon(Icons.photo_library_outlined),
              title:    const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                onAdd(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, FarmImage img) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Delete photo?'),
        content: const Text('This will remove the photo from your device and cloud storage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:     const Text('Cancel'),
          ),
          FilledButton(
            style:     FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () {
              Navigator.pop(context);
              onDelete(img);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}