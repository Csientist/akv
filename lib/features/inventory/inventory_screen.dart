import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/ledger_entry.dart';
import '../../data/repositories/ledger_repository.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _repo = LedgerRepository();
  late Future<List<InventoryItem>> _future;
  InventoryCategory? _filter; // null = show all

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _repo.getAllInventory();
    });
  }

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
            expandedHeight: 110,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Inventory', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: -0.5)),
                Text('Stock & Feed tracking', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.outline)),
              ]),
            ),
          ),
        ],
        body: FutureBuilder<List<InventoryItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)));
            }
            final all = snap.data ?? [];
            final lowStock = all.where((i) => i.isLowStock).toList();
            final displayed = _filter == null ? all : all.where((i) => i.category == _filter).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: [
                // Low stock alert
                if (lowStock.isNotEmpty) ...[
                  _LowStockBanner(count: lowStock.length, items: lowStock),
                  const SizedBox(height: 16),
                ],

                // Category filter chips
                _CategoryFilterRow(
                  selected: _filter,
                  onChanged: (cat) => setState(() => _filter = cat),
                ),
                const SizedBox(height: 16),

                // Items
                if (displayed.isEmpty)
                  _EmptyState(hasFilter: _filter != null)
                else
                  ...displayed.map((item) => _InventoryCard(
                        item: item,
                        onAdjust: (delta) {
                          _repo.adjustInventory(item: item, delta: delta).then((_) {
                            if (mounted) _load();
                          });
                        },
                      )),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2D6A4F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Item', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => _showAddSheet(),
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddInventorySheet(
        onSaved: (item) async {
          await _repo.addInventoryItem(item);
          _load();
        },
      ),
    );
  }
}

// ── Low Stock Banner ──────────────────────────────────────────────────────────

class _LowStockBanner extends StatelessWidget {
  final int count;
  final List<InventoryItem> items;
  const _LowStockBanner({required this.count, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 18),
          const SizedBox(width: 8),
          Text('$count item${count > 1 ? 's' : ''} below reorder level',
              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: items.map((i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(20)),
          child: Text('${i.itemName} (${i.quantity.toStringAsFixed(1)} ${i.unit.name})',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
        )).toList()),
      ]),
    );
  }
}

// ── Category Filter ───────────────────────────────────────────────────────────

class _CategoryFilterRow extends StatelessWidget {
  final InventoryCategory? selected;
  final ValueChanged<InventoryCategory?> onChanged;
  const _CategoryFilterRow({required this.selected, required this.onChanged});

  static const _icons = {
    InventoryCategory.FEED: Icons.grass,
    InventoryCategory.MEDICINE: Icons.medical_services_outlined,
    InventoryCategory.EQUIPMENT: Icons.build_outlined,
    InventoryCategory.SEED: Icons.eco_outlined,
    InventoryCategory.OTHER: Icons.category_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _Chip(label: 'All', icon: Icons.apps, selected: selected == null, onTap: () => onChanged(null)),
        ...InventoryCategory.values.map((cat) => _Chip(
          label: cat.name[0] + cat.name.substring(1).toLowerCase(),
          icon: _icons[cat]!,
          selected: selected == cat,
          onTap: () => onChanged(selected == cat ? null : cat),
        )),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2D6A4F) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0)),
          ),
          child: Row(children: [
            Icon(icon, size: 13, color: selected ? Colors.white : const Color(0xFF52796F)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF52796F))),
          ]),
        ),
      );
}

// ── Inventory Card ────────────────────────────────────────────────────────────

class _InventoryCard extends StatelessWidget {
  final InventoryItem item;
  final void Function(double delta) onAdjust;
  const _InventoryCard({required this.item, required this.onAdjust});

  static const _catColors = {
    InventoryCategory.FEED:      Color(0xFF2D6A4F),
    InventoryCategory.MEDICINE:  Color(0xFF9B2226),
    InventoryCategory.EQUIPMENT: Color(0xFF555B6E),
    InventoryCategory.SEED:      Color(0xFF5C6B2E),
    InventoryCategory.OTHER:     Color(0xFF6D6875),
  };

  @override
  Widget build(BuildContext context) {
    final catColor = _catColors[item.category] ?? const Color(0xFF2D6A4F);
    final levelColor = item.isLowStock ? Colors.red : (item.stockPercent < 0.5 ? Colors.orange : Colors.green);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.isLowStock ? Colors.red.shade200 : const Color(0xFFD8E8E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Category badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: catColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(item.category.name[0] + item.category.name.substring(1).toLowerCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: catColor, letterSpacing: 0.3)),
            ),
            const Spacer(),
            // Quantity + unit
            Text(
              '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity.toStringAsFixed(1)} ${item.unit.name}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: item.isLowStock ? Colors.red : const Color(0xFF1B4332)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(item.itemName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.notes!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          // Stock level bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.stockPercent,
              backgroundColor: const Color(0xFFF1F8F6),
              color: levelColor,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(
              item.isLowStock ? '⚠ Below reorder level (${item.reorderLevel.toStringAsFixed(0)} ${item.unit.name})' : 'Reorder at ${item.reorderLevel.toStringAsFixed(0)} ${item.unit.name}',
              style: TextStyle(fontSize: 11, color: item.isLowStock ? Colors.red : Colors.grey.shade500),
            ),
            const Spacer(),
            // Adjust buttons
            _AdjustBtn(icon: Icons.remove, color: Colors.red.shade400, onTap: () => _showAdjustDialog(context, negative: true)),
            const SizedBox(width: 6),
            _AdjustBtn(icon: Icons.add, color: const Color(0xFF2D6A4F), onTap: () => _showAdjustDialog(context, negative: false)),
          ]),
        ]),
      ),
    );
  }

  void _showAdjustDialog(BuildContext context, {required bool negative}) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(negative ? 'Use / Remove Stock' : 'Restock', style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${item.itemName} · Current: ${item.quantity} ${item.unit.name}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
            autofocus: true,
            decoration: InputDecoration(
              labelText: negative ? 'Amount to remove (${item.unit.name})' : 'Amount to add (${item.unit.name})',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: negative ? Colors.red.shade400 : const Color(0xFF2D6A4F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final val = double.tryParse(ctrl.text);
              if (val == null || val <= 0) return;
              Navigator.pop(context);
              onAdjust(negative ? -val : val);
            },
            child: Text(negative ? 'Remove' : 'Add'),
          ),
        ],
      ),
    );
  }
}

class _AdjustBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _AdjustBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  const _EmptyState({required this.hasFilter});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(children: [
            Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(hasFilter ? 'No items in this category' : 'No inventory items yet',
                style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Tap Add Item to get started', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ]),
        ),
      );
}

// ── Add Inventory Sheet ───────────────────────────────────────────────────────

class _AddInventorySheet extends StatefulWidget {
  final Future<void> Function(InventoryItem) onSaved;
  const _AddInventorySheet({required this.onSaved});
  @override
  State<_AddInventorySheet> createState() => _AddInventorySheetState();
}

class _AddInventorySheetState extends State<_AddInventorySheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _qtyCtrl      = TextEditingController();
  final _reorderCtrl  = TextEditingController();
  final _notesCtrl    = TextEditingController();
  InventoryCategory _category = InventoryCategory.FEED;
  InventoryUnit _unit = InventoryUnit.KG;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _qtyCtrl.dispose(); _reorderCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final item = InventoryItem(
        itemId: const Uuid().v4(),
        itemName: _nameCtrl.text.trim(),
        category: _category,
        quantity: double.parse(_qtyCtrl.text),
        unit: _unit,
        reorderLevel: double.tryParse(_reorderCtrl.text) ?? 0.0,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        createdAt: DateTime.now(),
      );
      await widget.onSaved(item);
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
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Add Inventory Item', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Item Name', prefixIcon: Icon(Icons.inventory_2_outlined, size: 18)),
              textCapitalization: TextCapitalization.words,
              validator: (v) => v!.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),

            // Category + Unit — stacked vertically to avoid overflow on small screens
            DropdownButtonFormField<InventoryCategory>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.label_outline, size: 18),
              ),
              items: InventoryCategory.values.map((c) => DropdownMenuItem(
                value: c,
                child: Text(c.name[0] + c.name.substring(1).toLowerCase()),
              )).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<InventoryUnit>(
              initialValue: _unit,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Unit',
                prefixIcon: Icon(Icons.straighten_outlined, size: 18),
              ),
              items: InventoryUnit.values.map((u) => DropdownMenuItem(
                value: u,
                child: Text(u.name),
              )).toList(),
              onChanged: (v) => setState(() => _unit = v!),
            ),
            const SizedBox(height: 12),

            Row(children: [
              Expanded(child: TextFormField(
                controller: _qtyCtrl,
                decoration: const InputDecoration(labelText: 'Current Qty', prefixIcon: Icon(Icons.numbers, size: 18)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                validator: (v) => v!.isEmpty ? 'Required' : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _reorderCtrl,
                decoration: const InputDecoration(labelText: 'Reorder At', prefixIcon: Icon(Icons.notification_important_outlined, size: 18)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              )),
            ]),
            const SizedBox(height: 12),

            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Store in dry place',
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
                  : const Text('Save Item', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}