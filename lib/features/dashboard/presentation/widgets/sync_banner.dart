// lib/features/dashboard/presentation/widgets/sync_banner.dart

import 'package:flutter/material.dart';
import '../../sync_debug_sheet.dart';

class SyncBanner extends StatelessWidget {
  final int pendingCount;
  
  const SyncBanner({super.key, required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    final isOnline = pendingCount == 0;
    
    // UI Theme based on sync state
    final bg     = isOnline ? const Color(0xFFD8F3DC) : Colors.orange.shade50;
    final border = isOnline ? const Color(0xFFB7E4C7) : Colors.orange.shade200;
    final dot    = isOnline ? const Color(0xFF2D6A4F) : Colors.orange;
    final label  = isOnline 
        ? 'All data synced' 
        : '$pendingCount record${pendingCount > 1 ? 's' : ''} pending sync';

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias, 
      child: InkWell(
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true, 
            backgroundColor: Colors.transparent,
            builder: (context) => const SyncDebugSheet(),
          );
        },
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOnline 
                    ? 'Your data is safely backed up to the cloud.'
                    : 'Syncing in background... Long-press for details.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _PulseDot(color: dot, animate: !isOnline),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: isOnline ? const Color(0xFF2D6A4F) : Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Icon(
                isOnline ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
                color: isOnline ? const Color(0xFF2D6A4F) : Colors.orange.shade700,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool animate;
  
  const _PulseDot({required this.color, required this.animate});
  
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { 
    _ctrl.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}