// lib/shared/widgets/status_badge.dart

import 'package:flutter/material.dart';
import '../../data/models/models.dart'; 

class StatusBadge extends StatelessWidget {
  final AssetStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == AssetStatus.active 
        ? const Color(0xFF2D6A4F)
        : status == AssetStatus.sold 
            ? Colors.blue.shade700
            : Colors.red.shade700;
            
    final bg = status == AssetStatus.active 
        ? const Color(0xFFD8F3DC)
        : status == AssetStatus.sold 
            ? Colors.blue.shade50
            : Colors.red.shade50;
            
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg, 
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.name.toUpperCase(), 
        style: TextStyle(
          fontSize: 10, 
          fontWeight: FontWeight.w700, 
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}