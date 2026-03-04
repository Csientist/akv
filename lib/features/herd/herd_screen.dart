import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/ledger_entry.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../services/session_manager.dart';

class HerdManagementScreen extends StatefulWidget {
  const HerdManagementScreen({super.key});
  @override
  State<HerdManagementScreen> createState() => _HerdManagementScreenState();
}

class _HerdManagementScreenState extends State<HerdManagementScreen>
    with SingleTickerProviderStateMixin {
  final _repo = LedgerRepository();
  late TabController _tabController;
  late Future<List<Asset>> _livestockFuture;
  late Future<List<Asset>> _cropFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  void _refresh() => setState(() {
    _livestockFuture = _repo.getActiveAssets(AssetCategory.livestock);
    _cropFuture = _repo.getActiveAssets(AssetCategory.crop);
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 56),
              title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Herd', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: -0.5)),
                Text('Livestock & Crops', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.outline)),
              ]),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.15)))),
                child: TabBar(
                  controller: _tabController,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.outline,
                  indicatorColor: scheme.primary,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: const [Tab(text: 'Livestock'), Tab(text: 'Crops')],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _AssetList(future: _livestockFuture, category: AssetCategory.livestock, onRefresh: _refresh, repo: _repo),
            _AssetList(future: _cropFuture, category: AssetCategory.crop, onRefresh: _refresh, repo: _repo),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2D6A4F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Register', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AddAssetSheet(onSaved: (a) async { await _repo.saveAsset(a); _refresh(); }),
        ),
      ),
    );
  }
}

// ── Asset List ────────────────────────────────────────────────────────────────

class _AssetList extends StatelessWidget {
  final Future<List<Asset>> future;
  final AssetCategory category;
  final VoidCallback onRefresh;
  final LedgerRepository repo;
  const _AssetList({required this.future, required this.category, required this.onRefresh, required this.repo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Asset>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          {return const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)));}
        final assets = snap.data ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            _SummaryBanner(assets: assets, category: category),
            const SizedBox(height: 20),
            const _SectionLabel('Animals'),
            const SizedBox(height: 10),
            if (assets.isEmpty)
              _EmptyState(category: category)
            else
              ...assets.map((a) => _AnimalCard(asset: a, onRefresh: onRefresh, repo: repo)),
          ],
        );
      },
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  final List<Asset> assets;
  final AssetCategory category;
  const _SummaryBanner({required this.assets, required this.category});
  @override
  Widget build(BuildContext context) {
    final total = assets.length;
    final healthy = assets.where((a) => a.healthNotes == null || a.healthNotes!.isEmpty).length;
    final attention = total - healthy;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1B4332), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _Stat('$total', category == AssetCategory.livestock ? 'Total Head' : 'Total Plots'),
        _Stat('$healthy', 'Healthy'),
        _Stat('$attention', 'Attention', highlight: attention > 0),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  final bool highlight;
  const _Stat(this.value, this.label, {this.highlight = false});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(color: highlight ? Colors.orangeAccent : Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
  ]);
}

// ── Animal Card ───────────────────────────────────────────────────────────────

class _AnimalCard extends StatelessWidget {
  final Asset asset;
  final VoidCallback onRefresh;
  final LedgerRepository repo;
  const _AnimalCard({required this.asset, required this.onRefresh, required this.repo});

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
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: const Color(0xFFD8F3DC), borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text(
                asset.tagName.isNotEmpty ? asset.tagName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
              )),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(asset.tagName.isNotEmpty ? asset.tagName : 'Unnamed',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFD8F3DC), borderRadius: BorderRadius.circular(6)),
                  child: Text(asset.breedType, style: const TextStyle(fontSize: 10, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
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
              ]),
              if (hasHealth) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(child: Text(asset.healthNotes!, style: const TextStyle(fontSize: 11, color: Colors.orange), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ])),
            // Edit button
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: const Color(0xFF52796F),
              tooltip: 'Edit',
              onPressed: () => _openEdit(context),
            ),
          ]),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnimalDetailSheet(asset: asset, repo: repo, onRefresh: onRefresh),
    );
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddAssetSheet(
        existing: asset,
        onSaved: (updated) async {
          await repo.updateAsset(updated);
          onRefresh();
        },
      ),
    );
  }
}

// ── Animal Detail Sheet ───────────────────────────────────────────────────────

class _AnimalDetailSheet extends StatefulWidget {
  final Asset asset;
  final LedgerRepository repo;
  final VoidCallback onRefresh;
  const _AnimalDetailSheet({required this.asset, required this.repo, required this.onRefresh});
  @override
  State<_AnimalDetailSheet> createState() => _AnimalDetailSheetState();
}

class _AnimalDetailSheetState extends State<_AnimalDetailSheet> {
  late Future<List<AssetEvent>> _eventsFuture;
  late Future<double> _totalMilk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _eventsFuture = widget.repo.getEventsForAsset(widget.asset.assetId);
      _totalMilk = widget.repo.getTotalMilkForAsset(widget.asset.assetId);
    });
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
            Row(children: [
              Container(width: 56, height: 56,
                  decoration: BoxDecoration(color: const Color(0xFFD8F3DC), borderRadius: BorderRadius.circular(16)),
                  child: Center(child: Text(a.tagName.isNotEmpty ? a.tagName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F))))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.tagName.isNotEmpty ? a.tagName : 'Unnamed',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(a.breedType, style: TextStyle(color: scheme.outline)),
              ])),
              _StatusBadge(a.status),
            ]),
            const SizedBox(height: 16),

            // Detail chips
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (a.dateOfBirth != null) ...[
                _Chip(Icons.cake_outlined, 'Age', a.displayAge),
                _Chip(Icons.calendar_today_outlined, 'Born',
                    '${a.dateOfBirth!.day.toString().padLeft(2,'0')}/${a.dateOfBirth!.month.toString().padLeft(2,'0')}/${a.dateOfBirth!.year}'),
              ],
              if (a.weightKg != null) _Chip(Icons.monitor_weight_outlined, 'Weight', '${a.weightKg!.toStringAsFixed(1)} kg'),
              _Chip(Icons.category_outlined, 'Category', a.category.name),
              if (a.category == AssetCategory.livestock)
                FutureBuilder<double>(
                  future: _totalMilk,
                  builder: (_, s) => _Chip(Icons.water_drop_outlined, 'Total Milk',
                      s.hasData ? '${s.data!.toStringAsFixed(1)} L' : '...'),
                ),
            ]),

            if (a.healthNotes != null && a.healthNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.medical_services_outlined, color: Colors.orange, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(a.healthNotes!, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            ],
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
            const _SectionLabel('Activity Timeline'),
            const SizedBox(height: 12),
            FutureBuilder<List<AssetEvent>>(
              future: _eventsFuture,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)));
                }
                final events = snap.data ?? [];
                if (events.isEmpty) {
                  return _EmptyTimeline();
                }
                return _Timeline(events: events);
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
      builder: (_) => _LogEventSheet(
        asset: widget.asset,
        repo: widget.repo,
        onSaved: () {
          _load();
          widget.onRefresh();
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AssetStatus status;
  const _StatusBadge(this.status);
  @override
  Widget build(BuildContext context) {
    final color = status == AssetStatus.active ? const Color(0xFF2D6A4F)
        : status == AssetStatus.SOLD ? Colors.blue.shade700
        : Colors.red.shade700;
    final bg = status == AssetStatus.active ? const Color(0xFFD8F3DC)
        : status == AssetStatus.SOLD ? Colors.blue.shade50
        : Colors.red.shade50;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _Chip(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFFF7FAF8), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E8E0))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: const Color(0xFF52796F)),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF52796F), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    ]),
  );
}

// ── Event Timeline ────────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  final List<AssetEvent> events;
  const _Timeline({required this.events});
  @override
  Widget build(BuildContext context) {
    return Column(children: events.asMap().entries.map((e) {
      final isLast = e.key == events.length - 1;
      return _TimelineItem(event: e.value, isLast: isLast);
    }).toList());
  }
}

class _TimelineItem extends StatelessWidget {
  final AssetEvent event;
  final bool isLast;
  const _TimelineItem({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Left: dot + line
        Column(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: const Color(0xFFD8F3DC), borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(event.emoji, style: const TextStyle(fontSize: 16))),
          ),
          if (!isLast)
            Expanded(child: Container(width: 2, color: const Color(0xFFD8E8E0), margin: const EdgeInsets.symmetric(vertical: 4))),
        ]),
        const SizedBox(width: 14),
        // Right: content
        Expanded(child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(event.displayLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              Text(_relDate(event.recordedAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]),
            if (event.notes != null && event.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(event.notes!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            if (event.metadata != null && event.metadata!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: event.metadata!.entries.map((m) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFF1F8F6), borderRadius: BorderRadius.circular(6)),
                child: Text('${m.key}: ${m.value}', style: const TextStyle(fontSize: 11, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w600)),
              )).toList()),
            ],
          ]),
        )),
      ]),
    );
  }

  String _relDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays == 1)     return 'Yesterday';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _EmptyTimeline extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Icon(Icons.timeline, size: 40, color: Colors.grey.shade300),
        const SizedBox(height: 10),
        Text('No activity logged yet', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Tap "Log Activity" to add the first entry', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      ]),
    ),
  );
}

// ── Log Event Sheet ───────────────────────────────────────────────────────────

class _LogEventSheet extends StatefulWidget {
  final Asset asset;
  final LedgerRepository repo;
  final VoidCallback onSaved;
  const _LogEventSheet({required this.asset, required this.repo, required this.onSaved});
  @override
  State<_LogEventSheet> createState() => _LogEventSheetState();
}

class _LogEventSheetState extends State<_LogEventSheet> {
  String? _selectedType;
  final _notesCtrl  = TextEditingController();
  final _meta1Ctrl  = TextEditingController(); // context-specific field 1
  final _meta2Ctrl  = TextEditingController(); // context-specific field 2
  final userId = SessionManager.instance.currentUserId;

  DateTime _recordedAt = DateTime.now();
  bool _saving = false;
  MilkSession _milkSession = MilkSession.AM;

  bool get _isLivestock => widget.asset.category == AssetCategory.livestock;

  // Event types per category
  static const _livestockTypes = [
    ('vaccination',    '💉', 'Vaccination'),
    ('deworming',      '💊', 'Deworming'),
    ('vetVisit',       '🏥', 'Vet Visit'),
    ('medication',     '💊', 'Medication'),
    ('injury',         '🩹', 'Injury'),
    ('mating',         '🔗', 'Mating'),
    ('pregnancyCheck', '🔬', 'Pregnancy Check'),
    ('birth',          '🐣', 'Birth'),
    ('feedChange',     '🌾', 'Feed Change'),
    ('supplement',     '🧪', 'Supplement'),
    ('weightCheck',    '⚖️',  'Weight Check'),
    ('milkLog',        '🥛', 'Milk Log'),
    ('sold',           '💰', 'Sold'),
    ('deceased',       '🕊️', 'Deceased'),
  ];

  static const _cropTypes = [
    ('planting',   '🌱', 'Planting'),
    ('weeding',    '🪴', 'Weeding'),
    ('fertilizer', '🧴', 'Fertilizer'),
    ('pesticide',  '🪣', 'Pesticide'),
    ('irrigation', '💧', 'Irrigation'),
    ('harvest',    '🌾', 'Harvest'),
    ('cropLoss',   '⚠️', 'Crop Loss'),
  ];

  List<(String, String, String)> get _types => _isLivestock ? _livestockTypes : _cropTypes;

  // Returns extra metadata fields based on selected type
  Widget _metaFields() {
    switch (_selectedType) {
      case 'weightCheck':
        return _MetaField(ctrl: _meta1Ctrl, label: 'Weight (kg)', hint: 'e.g. 340', keyboard: TextInputType.number);
      case 'milkLog':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Litres collected', hint: 'e.g. 12.5', keyboard: TextInputType.number),
          const SizedBox(height: 12),
          const Text('Session', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2D6A4F), letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Row(children: MilkSession.values.map((s) {
            final sel = _milkSession == s;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _milkSession = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF2D6A4F) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0)),
                ),
                child: Center(child: Text(s.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                    color: sel ? Colors.white : const Color(0xFF52796F)))),
              ),
            ));
          }).toList()),
        ]);
      case 'vaccination':
      case 'deworming':
      case 'medication':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Drug / Vaccine name', hint: 'e.g. Ivermectin'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Dose / Quantity', hint: 'e.g. 5ml'),
        ]);
      case 'mating':
        return _MetaField(ctrl: _meta1Ctrl, label: 'Sire / Bull ID or Name', hint: 'e.g. Bull-007');
      case 'birth':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Number of offspring', hint: 'e.g. 1', keyboard: TextInputType.number),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Offspring tag(s)', hint: 'e.g. Calf-001'),
        ]);
      case 'feedChange':
        return _MetaField(ctrl: _meta1Ctrl, label: 'New feed type', hint: 'e.g. Silage + Dairy Meal');
      case 'harvest':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Yield quantity', hint: 'e.g. 40'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Unit', hint: 'e.g. bags, kg, crates'),
        ]);
      case 'fertilizer':
      case 'pesticide':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Product name', hint: 'e.g. CAN, Dithane M-45'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Quantity applied', hint: 'e.g. 50kg, 2L'),
        ]);
      case 'sold':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Buyer name', hint: 'e.g. Kamau Dairy'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Sale amount (KES)', hint: 'e.g. 85000', keyboard: TextInputType.number),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  Map<String, dynamic> _buildMetadata() {
    final m = <String, dynamic>{};
    switch (_selectedType) {
      case 'weightCheck':
        if (_meta1Ctrl.text.isNotEmpty) m['weight_kg'] = double.tryParse(_meta1Ctrl.text);
      case 'milkLog':
        if (_meta1Ctrl.text.isNotEmpty) m['litres'] = double.tryParse(_meta1Ctrl.text);
        m['session'] = _milkSession.name;
      case 'vaccination':
      case 'deworming':
      case 'medication':
        if (_meta1Ctrl.text.isNotEmpty) m['drug'] = _meta1Ctrl.text.trim();
        if (_meta2Ctrl.text.isNotEmpty) m['dose'] = _meta2Ctrl.text.trim();
      case 'mating':
        if (_meta1Ctrl.text.isNotEmpty) m['sire'] = _meta1Ctrl.text.trim();
      case 'birth':
        if (_meta1Ctrl.text.isNotEmpty) m['offspring_count'] = int.tryParse(_meta1Ctrl.text);
        if (_meta2Ctrl.text.isNotEmpty) m['offspring_tags'] = _meta2Ctrl.text.trim();
      case 'feedChange':
        if (_meta1Ctrl.text.isNotEmpty) m['feed_type'] = _meta1Ctrl.text.trim();
      case 'harvest':
        if (_meta1Ctrl.text.isNotEmpty) m['yield'] = _meta1Ctrl.text.trim();
        if (_meta2Ctrl.text.isNotEmpty) m['unit'] = _meta2Ctrl.text.trim();
      case 'fertilizer':
      case 'pesticide':
        if (_meta1Ctrl.text.isNotEmpty) m['product'] = _meta1Ctrl.text.trim();
        if (_meta2Ctrl.text.isNotEmpty) m['quantity'] = _meta2Ctrl.text.trim();
      case 'sold':
        if (_meta1Ctrl.text.isNotEmpty) m['buyer'] = _meta1Ctrl.text.trim();
        if (_meta2Ctrl.text.isNotEmpty) m['amount_kes'] = double.tryParse(_meta2Ctrl.text);
    }
    return m;
  }

  Future<void> _save() async {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an activity type')));
      return;
    }
    setState(() => _saving = true);
    try {
      final event = AssetEvent(
        eventId: const Uuid().v4(),
        assetId: widget.asset.assetId,
        eventType: _selectedType!,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        metadata: _buildMetadata().isNotEmpty ? _buildMetadata() : null,
        recordedAt: _recordedAt,
        createdBy: userId,
        createdAt: DateTime.now(),
      );

      // If milk log, also save to milk_logs table for reporting
      if (_selectedType == 'milkLog' && _meta1Ctrl.text.isNotEmpty) {
        final litres = double.tryParse(_meta1Ctrl.text) ?? 0;
        if (litres > 0) {
          await widget.repo.saveMilkLog(MilkLog(
            logId: const Uuid().v4(),
            assetId: widget.asset.assetId,
            litres: litres,
            session: _milkSession,
            recordedAt: _recordedAt,
            notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
            createdBy: userId,
            createdAt: DateTime.now()
          ));
        }
      }

      await widget.repo.saveAssetEvent(event);
      if (mounted) { Navigator.pop(context); widget.onSaved(); }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose(); _meta1Ctrl.dispose(); _meta2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(children: [
          Text('Log Activity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(widget.asset.tagName, style: const TextStyle(color: Color(0xFF2D6A4F), fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 20),

        // Event type grid
        const _SectionLabel('Activity Type'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _types.map((t) {
            final (type, emoji, label) = t;
            final sel = _selectedType == type;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedType = type;
                _meta1Ctrl.clear(); _meta2Ctrl.clear();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF2D6A4F) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : const Color(0xFF52796F))),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Context-specific metadata fields
        if (_selectedType != null) ...[
          _metaFields(),
          const SizedBox(height: 14),
        ],

        // Date picker
        _DateRow(date: _recordedAt, onChanged: (d) => setState(() => _recordedAt = d)),
        const SizedBox(height: 14),

        // Notes
        TextFormField(
          controller: _notesCtrl,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'Any extra details...',
            prefixIcon: Icon(Icons.notes_outlined, size: 18),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D6A4F), foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text('Save Activity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        const SizedBox(height: 8),
      ])),
    );
  }
}

class _DateRow extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  const _DateRow({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
          helpText: 'When did this happen?',
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: const Color(0xFF2D6A4F))),
            child: child!,
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Colors.white,
            border: Border.all(color: const Color(0xFFD8E8E0)), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF2D6A4F)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Date', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF52796F))),
            Text('${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const Spacer(),
          Text('Tap to change', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ]),
      ),
    );
  }
}

class _MetaField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final TextInputType keyboard;
  const _MetaField({required this.ctrl, required this.label, required this.hint, this.keyboard = TextInputType.text});
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}

// ── Add / Edit Asset Sheet ────────────────────────────────────────────────────

class _AddAssetSheet extends StatefulWidget {
  final Asset? existing;
  final Future<void> Function(Asset) onSaved;
  const _AddAssetSheet({this.existing, required this.onSaved});
  @override
  State<_AddAssetSheet> createState() => _AddAssetSheetState();
}

class _AddAssetSheetState extends State<_AddAssetSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tagCtrl;
  late final TextEditingController _breedCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _notesCtrl;
  late AssetCategory _category;
  late AssetStatus _status;
  DateTime? _dateOfBirth;
  bool _saving = false;
  final userId = SessionManager.instance.currentUserId;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tagCtrl   = TextEditingController(text: e?.tagName ?? '');
    _breedCtrl = TextEditingController(text: e?.breedType ?? '');
    _weightCtrl = TextEditingController(text: e?.weightKg?.toStringAsFixed(1) ?? '');
    _notesCtrl = TextEditingController(text: e?.healthNotes ?? '');
    _category  = e?.category ?? AssetCategory.livestock;
    _status    = e?.status ?? AssetStatus.active;
    _dateOfBirth = e?.dateOfBirth;
  }

  @override
  void dispose() {
    _tagCtrl.dispose(); _breedCtrl.dispose(); _weightCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final asset = Asset(
        assetId: widget.existing?.assetId ?? const Uuid().v4(),
        tagName: _tagCtrl.text.trim(),
        category: _category,
        breedType: _breedCtrl.text.trim(),
        status: _status,
        weightKg: _weightCtrl.text.isNotEmpty ? double.tryParse(_weightCtrl.text) : null,
        dateOfBirth: _dateOfBirth,
        healthNotes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        createdBy: userId,
        createdAt: widget.existing?.createdAt ?? DateTime.now().toUtc(),
      );
      await widget.onSaved(asset);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(_isEdit ? 'Edit Animal / Crop' : 'Register Animal / Crop',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),

          // Category
          Row(children: AssetCategory.values.map((cat) {
            final sel = _category == cat;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _category = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF2D6A4F) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(cat == AssetCategory.livestock ? Icons.pets : Icons.grass, size: 16,
                      color: sel ? Colors.white : const Color(0xFF52796F)),
                  const SizedBox(width: 6),
                  Text(cat.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                      color: sel ? Colors.white : const Color(0xFF52796F))),
                ]),
              ),
            ));
          }).toList()),
          const SizedBox(height: 14),

          TextFormField(controller: _tagCtrl,
              decoration: const InputDecoration(labelText: 'Tag / Name', hintText: 'e.g. Daisy, Bull-003', prefixIcon: Icon(Icons.label_outline, size: 18)),
              validator: (v) => v!.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _breedCtrl,
              decoration: const InputDecoration(labelText: 'Breed / Variety', hintText: 'e.g. Friesian, H614D Maize', prefixIcon: Icon(Icons.biotech_outlined, size: 18)),
              validator: (v) => v!.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: TextFormField(
              controller: _weightCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
              decoration: const InputDecoration(labelText: 'Weight (kg)', hintText: 'e.g. 340', prefixIcon: Icon(Icons.monitor_weight_outlined, size: 18)),
            )),
            const SizedBox(width: 12),
            Expanded(child: _DatePickerField(
              label: 'Date of Birth',
              selected: _dateOfBirth,
              onPicked: (d) => setState(() => _dateOfBirth = d),
            )),
          ]),
          const SizedBox(height: 12),

          // Status (edit only)
          if (_isEdit) ...[
            DropdownButtonFormField<AssetStatus>(
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.info_outline, size: 18)),
              items: AssetStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 12),
          ],

          TextFormField(controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Health Notes (optional)', hintText: 'e.g. Vaccinated June 2025', prefixIcon: Icon(Icons.medical_services_outlined, size: 18)),
              maxLines: 2),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D6A4F), foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : Text(_isEdit ? 'Save Changes' : 'Register', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(height: 8),
        ])),
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2D6A4F), letterSpacing: 1.6));
}

class _EmptyState extends StatelessWidget {
  final AssetCategory category;
  const _EmptyState({required this.category});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(children: [
        Icon(category == AssetCategory.livestock ? Icons.pets : Icons.grass, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('No ${category == AssetCategory.livestock ? 'livestock' : 'crops'} registered',
            style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Tap Register to add one', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
      ]),
    ),
  );
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? selected;
  final ValueChanged<DateTime> onPicked;
  const _DatePickerField({required this.label, required this.selected, required this.onPicked});

  String get _display => selected == null ? 'Tap to select'
      : '${selected!.day.toString().padLeft(2,'0')}/${selected!.month.toString().padLeft(2,'0')}/${selected!.year}';

  @override
  Widget build(BuildContext context) {
    final hasValue = selected != null;
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selected ?? DateTime.now().subtract(const Duration(days: 365)),
          firstDate: DateTime(2000), lastDate: DateTime.now(),
          helpText: 'Select Date of Birth',
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: const Color(0xFF2D6A4F))),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: hasValue ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0), width: hasValue ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(Icons.cake_outlined, size: 18, color: hasValue ? const Color(0xFF2D6A4F) : Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 10, color: hasValue ? const Color(0xFF2D6A4F) : Colors.grey.shade500, fontWeight: FontWeight.w600)),
            const SizedBox(height: 1),
            Text(_display, style: TextStyle(fontSize: 13, color: hasValue ? const Color(0xFF1B4332) : Colors.grey.shade400,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400)),
          ])),
        ]),
      ),
    );
  }
}