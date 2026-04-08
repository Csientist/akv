// lib/shared/widgets/app_date_picker.dart

import 'package:flutter/material.dart';

class AppDatePicker extends StatelessWidget {
  final String label;
  final DateTime? selected;
  final ValueChanged<DateTime> onPicked;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const AppDatePicker({
    super.key,
    required this.label,
    required this.selected,
    required this.onPicked,
    this.firstDate,
    this.lastDate,
  });

  String get _display => selected == null
      ? 'Tap to select'
      : '${selected!.day.toString().padLeft(2, '0')}/${selected!.month.toString().padLeft(2, '0')}/${selected!.year}';

  @override
  Widget build(BuildContext context) {
    final hasValue = selected != null;
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selected ?? DateTime.now(),
          firstDate: firstDate ?? DateTime(2000),
          lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
                colorScheme: Theme.of(ctx)
                    .colorScheme
                    .copyWith(primary: const Color(0xFF2D6A4F))),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: hasValue ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0),
              width: hasValue ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 18,
                color: hasValue ? const Color(0xFF2D6A4F) : Colors.grey.shade400),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: hasValue
                              ? const Color(0xFF2D6A4F)
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(_display,
                      style: TextStyle(
                          fontSize: 13,
                          color: hasValue
                              ? const Color(0xFF1B4332)
                              : Colors.grey.shade400,
                          fontWeight:
                              hasValue ? FontWeight.w600 : FontWeight.w400)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}