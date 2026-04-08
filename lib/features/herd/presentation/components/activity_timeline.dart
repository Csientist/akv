// lib/features/herd/presentation/components/activity_timeline.dart

import 'package:flutter/material.dart';
import '../../../../data/models/models.dart';

class ActivityTimeline extends StatelessWidget {
  final List<AssetEvent> events;
  final void Function(AssetEvent) onEdit;

  const ActivityTimeline({super.key, required this.events, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const EmptyTimeline();

    return Column(
      children: events.asMap().entries.map((e) {
        final isLast = e.key == events.length - 1;
        return TimelineItem(event: e.value, isLast: isLast, onEdit: onEdit);
      }).toList()
    );
  }
}

class TimelineItem extends StatelessWidget {
  final AssetEvent event;
  final bool isLast;
  final void Function(AssetEvent) onEdit;

  const TimelineItem({super.key, required this.event, required this.isLast, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final dateTo   = event.metadata?['date_to'] as String?;
    final dateLabel = dateTo != null
        ? '${_fmt(event.recordedAt)} → $dateTo'
        : _relDate(event.recordedAt);
    final label = event.eventType == 'other'
        ? (event.metadata?['activity'] as String? ?? 'Other')
        : event.displayLabel;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Column(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFFD8F3DC), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(event.emoji, style: const TextStyle(fontSize: 16))),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: const Color(0xFFD8E8E0), margin: const EdgeInsets.symmetric(vertical: 4))),
            ]
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                      GestureDetector(
                        onTap: () => onEdit(event),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.edit_outlined, size: 15, color: Colors.grey.shade400),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(dateLabel, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ]
                  ),
                  if (event.notes != null && event.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(event.notes!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                  if (event.metadata != null && event.metadata!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, 
                      children: event.metadata!.entries
                        .where((m) => m.key != 'date_to' && m.key != 'activity')
                        .map((m) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFF1F8F6), borderRadius: BorderRadius.circular(6)),
                          child: Text('${m.key}: ${m.value}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w600)),
                        )).toList()
                    ),
                  ],
                ]
              ),
            )
          ),
        ]
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';

  String _relDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays == 1)     return 'Yesterday';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    return _fmt(dt);
  }
}

class EmptyTimeline extends StatelessWidget {
  const EmptyTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.timeline, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text('No activity logged yet', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Tap "Log Activity" to add the first entry', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ]
        ),
      ),
    );
  }
}