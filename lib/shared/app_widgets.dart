import 'package:flutter/material.dart';

// ── Section Label ─────────────────────────────────────────────────────────────
/// Single source of truth for the ALL-CAPS section headers used across screens.
/// Previously duplicated in dashboard_screen, herd_screen, and sales_record_screen.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
        ),
      );
}

// ── Amount Formatter ──────────────────────────────────────────────────────────
/// KES amount formatter shared by Dashboard and Sale screens.
String formatKes(double amount) {
  if (amount >= 1_000_000) return 'KES ${(amount / 1_000_000).toStringAsFixed(1)}M';
  if (amount >= 1_000)     return 'KES ${(amount / 1_000).toStringAsFixed(1)}k';
  return 'KES ${amount.toStringAsFixed(0)}';
}

// ── Empty State ───────────────────────────────────────────────────────────────
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(children: [
            Icon(icon, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}