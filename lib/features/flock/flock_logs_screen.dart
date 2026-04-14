// lib/features/flock/flock_logs_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/app_refresh_service.dart';
import '../../shared/widgets/shared_widgets.dart';


class FlockLogsScreen extends StatefulWidget {
  const FlockLogsScreen({super.key});

  @override
  State<FlockLogsScreen> createState() => _FlockLogsScreenState();
}

class _FlockLogsScreenState extends State<FlockLogsScreen> {
  final _repo = FlockRepository();
  late Future<List<FlockLog>> _logsFuture;
  StreamSubscription<void>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshSub = AppRefreshService.instance.ticks.listen((_) {
        if (mounted) _loadData();
      });
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _logsFuture = _repo.getFlockLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            expandedHeight: 110,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Feed & Pasture',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                          letterSpacing: -0.5)),
                  Text('Flock Nutrition & Rotation',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: scheme.outline)),
                ],
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                  height: 1, color: scheme.outline.withValues(alpha: 0.15)),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<List<FlockLog>>(
              future: _logsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 100),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF2D6A4F))),
                  );
                }

                final logs = snap.data ?? [];

                if (logs.isEmpty) {
                  return const _EmptyFlockState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return _FlockLogCard(log: log);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2D6A4F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Log Feed',
            style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AddFlockLogSheet(
            repo: _repo,
            onSaved: _loadData,
          ),
        ),
      ),
    );
  }
}

// ── Log Card ─────────────────────────────────────────────────────────────────

class _FlockLogCard extends StatelessWidget {
  final FlockLog log;
  const _FlockLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasIssues = log.waterIssue;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: hasIssues ? Colors.red.shade200 : const Color(0xFFD8E8E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8F3DC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.grass,
                      size: 20, color: Color(0xFF2D6A4F)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.paddockInUse?.isNotEmpty == true
                            ? log.paddockInUse!
                            : 'General Pasture',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmtDate(log.recordedAt),
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                if (log.feedCost > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Cost',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text(
                        'KES ${log.feedCost.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B4332)),
                      ),
                    ],
                  )
              ],
            ),
            const SizedBox(height: 14),

            // Details Row
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (log.animalsOnPasture != null)
                  _DetailChip(
                    icon: Icons.pets,
                    label: '${log.animalsOnPasture} Head',
                  ),
                if (log.supplFeedType != null && log.supplFeedType!.isNotEmpty)
                  _DetailChip(
                    icon: Icons.inventory_2_outlined,
                    label: log.supplFeedType!,
                    value: log.qtyFed != null ? '${log.qtyFed} kg' : null,
                  ),
              ],
            ),

            // Alerts Row
            if (log.mineralBlockProvided || log.waterIssue) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (log.mineralBlockProvided)
                    _StatusPill(
                      label: 'Minerals Given',
                      icon: Icons.check_circle_outline,
                      color: Colors.blue.shade700,
                      bgColor: Colors.blue.shade50,
                    ),
                  if (log.mineralBlockProvided && log.waterIssue)
                    const SizedBox(width: 8),
                  if (log.waterIssue)
                    _StatusPill(
                      label: 'Water Issue',
                      icon: Icons.warning_amber_rounded,
                      color: Colors.red.shade700,
                      bgColor: Colors.red.shade50,
                    ),
                ],
              ),
            ],

            if (log.notes != null && log.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                log.notes!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              )
            ]
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _DetailChip({required this.icon, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          value != null ? '$label ($value)' : label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _StatusPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _EmptyFlockState extends StatelessWidget {
  const _EmptyFlockState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.grass, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No pasture logs yet',
                style: TextStyle(
                    color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Track paddock rotations & feeding',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Add Log Sheet ────────────────────────────────────────────────────────────

class _AddFlockLogSheet extends StatefulWidget {
  final FlockRepository repo;
  final VoidCallback onSaved;

  const _AddFlockLogSheet({required this.repo, required this.onSaved});

  @override
  State<_AddFlockLogSheet> createState() => _AddFlockLogSheetState();
}

class _AddFlockLogSheetState extends State<_AddFlockLogSheet> {
  final _formKey = GlobalKey<FormState>();

  final _paddockCtrl = TextEditingController();
  final _animalsCtrl = TextEditingController();
  final _supplFeedCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _recordedAt = DateTime.now();
  bool _mineralBlock = false;
  bool _waterIssue = false;
  bool _saving = false;

  @override
  void dispose() {
    _paddockCtrl.dispose();
    _animalsCtrl.dispose();
    _supplFeedCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final log = FlockLog(
        logId: const Uuid().v4(),
        recordedAt: _recordedAt,
        paddockInUse:
            _paddockCtrl.text.isNotEmpty ? _paddockCtrl.text.trim() : null,
        animalsOnPasture: int.tryParse(_animalsCtrl.text),
        supplFeedType:
            _supplFeedCtrl.text.isNotEmpty ? _supplFeedCtrl.text.trim() : null,
        qtyFed: double.tryParse(_qtyCtrl.text),
        feedCost: double.tryParse(_costCtrl.text) ?? 0.0,
        mineralBlockProvided: _mineralBlock,
        waterIssue: _waterIssue,
        notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text.trim() : null,
        createdBy: '', // Repository overrides this with _uid
        createdAt: DateTime.now(),
      );

      await widget.repo.saveFlockLog(log);
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Log Feed & Pasture',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),

              // Date Picker
              AppDatePicker(
                label: 'Log Date',
                selected: _recordedAt,
                onPicked: (d) => setState(() => _recordedAt = d),
              ),
              const SizedBox(height: 14),

              // Paddock & Animals
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _paddockCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Paddock / Area',
                        hintText: 'e.g. North Field',
                        prefixIcon: Icon(Icons.grass, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _animalsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Head Count',
                        hintText: 'e.g. 150',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              const Text('SUPPLEMENTAL FEEDING',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D6A4F),
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),

              TextFormField(
                controller: _supplFeedCtrl,
                decoration: const InputDecoration(
                  labelText: 'Feed Type',
                  hintText: 'e.g. Lucerne Hay, Dairy Meal',
                  prefixIcon: Icon(Icons.inventory_2_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _qtyCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,1}'))
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Quantity (kg)',
                        hintText: 'e.g. 50',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _costCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}'))
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Est. Cost (KES)',
                        hintText: 'e.g. 1500',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Toggles
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD8E8E0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Mineral/Salt Block Provided?',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      value: _mineralBlock,
                      activeThumbColor: const Color(0xFF2D6A4F),
                      onChanged: (v) => setState(() => _mineralBlock = v),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Water Issue Detected?',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Dry trough, broken pipe, etc.',
                          style: TextStyle(fontSize: 11)),
                      value: _waterIssue,
                      activeThumbColor: Colors.red,
                      onChanged: (v) => setState(() => _waterIssue = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Pasture condition, rotation plans...',
                  prefixIcon: Icon(Icons.notes, size: 18),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Save Log',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
