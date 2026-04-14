// lib/features/herd/presentation/sheets/animal_detail_sheet.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../data/models/models.dart';
import '../../../../data/repositories/repositories.dart';
import '../../../../services/image_service.dart';
import '../../../../services/asset_image_widget.dart';
import '../../../../services/session_manager.dart';
import '../../../../shared/widgets/shared_widgets.dart';
import '../components/activity_timeline.dart';
import 'log_event_sheet.dart';

class AnimalDetailSheet extends StatefulWidget {
  final Asset asset;
  final HerdRepository repo;
  final VoidCallback onRefresh;
  
  const AnimalDetailSheet({
    super.key, 
    required this.asset, 
    required this.repo, 
    required this.onRefresh
  });

  @override
  State<AnimalDetailSheet> createState() => _AnimalDetailSheetState();
}

class _AnimalDetailSheetState extends State<AnimalDetailSheet> {
  late Future<List<AssetEvent>> _eventsFuture;
  late Future<double> _totalMilk;
  List<FarmImage> _images = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadImages();
  }

  void _load() {
    final events = widget.repo.getEventsForAsset(widget.asset.assetId);
    final milk   = widget.repo.getTotalMilkForAsset(widget.asset.assetId);
    if (mounted) {
      setState(() {
        _eventsFuture = events;
        _totalMilk    = milk;
      });
    }
  }

  Future<void> _loadImages() async {
    final imgs = await ImageService.instance.getImages(
      entityType: ImageEntityType.asset,
      entityId:   widget.asset.assetId,
    );
    if (mounted) setState(() => _images = imgs);
  }

  Future<void> _pickImage(ImageSource source) async {
    final img = await ImageService.instance.pickAndSave(
      entityType: ImageEntityType.asset,
      entityId:   widget.asset.assetId,
      createdBy:  SessionManager.instance.currentUserId,
      source:     source,
    );
    if (img != null) await _loadImages();
  }

  Future<void> _deleteImage(FarmImage img) async {
    await ImageService.instance.delete(img);
    await _loadImages();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    final scheme = Theme.of(context).colorScheme;
    
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            // Handle
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                AssetThumbnail(assetId: a.assetId, tagName: a.tagName, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children: [
                      Text(a.tagName.isNotEmpty ? a.tagName : 'Unnamed',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(a.breedType, style: TextStyle(color: scheme.outline)),
                    ]
                  )
                ),
                StatusBadge(status: a.status),
              ]
            ),
            const SizedBox(height: 16),

            // Detail chips
            Wrap(
              spacing: 10, 
              runSpacing: 10, 
              children: [
                if (a.dateOfBirth != null) ...[
                  _DetailChip(Icons.cake_outlined, 'Age', a.displayAge),
                  _DetailChip(Icons.calendar_today_outlined, 'Born',
                      '${a.dateOfBirth!.day.toString().padLeft(2,'0')}/${a.dateOfBirth!.month.toString().padLeft(2,'0')}/${a.dateOfBirth!.year}'),
                ],
                if (a.weightKg != null) _DetailChip(Icons.monitor_weight_outlined, 'Weight', '${a.weightKg!.toStringAsFixed(1)} kg'),
                _DetailChip(Icons.category_outlined, 'Category', a.category.name.toUpperCase()),
                
                if (a.category == AssetCategory.livestock)
                  FutureBuilder<double>(
                    future: _totalMilk,
                    builder: (_, s) => _DetailChip(
                      Icons.water_drop_outlined, 
                      'Total Milk',
                      s.hasData ? '${s.data!.toStringAsFixed(1)} L' : '...'
                    ),
                  ),
              ]
            ),

            if (a.healthNotes != null && a.healthNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.medical_services_outlined, color: Colors.orange, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a.healthNotes!, style: const TextStyle(fontSize: 13))),
                  ]
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Photos
            const SectionLabel('Photos'),
            const SizedBox(height: 10),
            AssetImageStrip(
              images:    _images,
              maxImages: 3,
              onAdd:     (source) => _pickImage(source),
              onDelete:  (img)    => _deleteImage(img),
            ),
            const SizedBox(height: 20),

            // Log event button
            ElevatedButton.icon(
              onPressed: () => _showLogEventSheet(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6A4F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Log Activity', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 24),

            // Event timeline
            const SectionLabel('Activity Timeline'),
            const SizedBox(height: 12),
            FutureBuilder<List<AssetEvent>>(
              future: _eventsFuture,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)));
                }
                final events = snap.data ?? [];
                return ActivityTimeline(
                  events: events,
                  onEdit: (e) => _showEditEventSheet(context, e),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLogEventSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogEventSheet(
        asset: widget.asset,
        repo: widget.repo,
        onSaved: () { _load(); widget.onRefresh(); },
      ),
    );
  }

  void _showEditEventSheet(BuildContext context, AssetEvent event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogEventSheet(
        asset:    widget.asset,
        repo:     widget.repo,
        existing: event,
        onSaved:  () { _load(); widget.onRefresh(); },
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailChip(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF8), 
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E8E0))
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, 
        children: [
          Icon(icon, size: 14, color: const Color(0xFF52796F)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF52796F), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ]
          ),
        ]
      ),
    );
  }
}