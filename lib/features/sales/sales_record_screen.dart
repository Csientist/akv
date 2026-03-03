import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/ledger_entry.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../services/sync_service.dart';

const _uuid = Uuid();

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with SingleTickerProviderStateMixin {
  // Tab controller: Record Sale | History
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF7),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 56),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sales',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Record & track your transactions',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: scheme.outline.withValues())),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.outline,
                  indicatorColor: scheme.primary,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Record Sale'),
                    Tab(text: 'History'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: const [
            _RecordSaleTab(),
            _SalesHistoryTab(),
          ],
        ),
      ),
    );
  }
}

// ── Record Sale Tab ───────────────────────────────────────────────────────────

class _RecordSaleTab extends StatefulWidget {
  const _RecordSaleTab();

  @override
  State<_RecordSaleTab> createState() => _RecordSaleTabState();
}

class _RecordSaleTabState extends State<_RecordSaleTab> {
  final _formKey = GlobalKey<FormState>();
  final _repo = LedgerRepository();

  // Controllers
  final _customerCtrl   = TextEditingController();
  final _amountCtrl     = TextEditingController();
  final _descCtrl       = TextEditingController();
  final _mpesaCodeCtrl  = TextEditingController();
  final _kraRefCtrl     = TextEditingController();

  // State
  PaymentMethod _paymentMethod = PaymentMethod.MPESA;
  bool _isKraCertified = false;
  bool _isSaving = false;
  String? _successMessage;

  @override
  void dispose() {
    _customerCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _mpesaCodeCtrl.dispose();
    _kraRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isSaving = true; _successMessage = null; });

    try {
      final now      = DateTime.now();
      final sourceId = _uuid.v4(); // In production: link to an actual Asset ID
      final txnId    = _uuid.v4();
      final amount   = double.parse(_amountCtrl.text.trim());

      // Build metadata (M-PESA code, notes)
      final metadata = <String, dynamic>{
        'description': _descCtrl.text.trim(),
        if (_paymentMethod == PaymentMethod.MPESA && _mpesaCodeCtrl.text.isNotEmpty)
          'mpesa_code': _mpesaCodeCtrl.text.trim().toUpperCase(),
      };

      final financial = Financial(
        transactionId: txnId,
        customerSupplierName: _customerCtrl.text.trim(),
        paymentMethod: _paymentMethod,
        amount: amount,
        isKraCertified: _isKraCertified,
        kraReference: _isKraCertified ? _kraRefCtrl.text.trim() : null,
        createdAt: now,
      );

      await _repo.recordSale(
        sourceId: sourceId,
        amount: amount,
        financial: financial,
        metadata: metadata,
      );

      // Non-blocking background sync
      SyncService().processQueue();

      setState(() {
        _successMessage = 'Sale of KES ${_amountCtrl.text} recorded ✓';
      });

      // Reset form
      _formKey.currentState!.reset();
      _customerCtrl.clear();
      _amountCtrl.clear();
      _descCtrl.clear();
      _mpesaCodeCtrl.clear();
      _kraRefCtrl.clear();
      setState(() { _paymentMethod = PaymentMethod.MPESA; _isKraCertified = false; });

    } catch (e) {
      _showError('Failed to record sale. Saved locally and will retry.');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFE63946),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // Success banner
            if (_successMessage != null) ...[
              _SuccessBanner(message: _successMessage!),
              const SizedBox(height: 20),
            ],

            // ── Section: Customer Details ──────────────────────────────────
            _SectionLabel(label: 'Customer Details'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _customerCtrl,
              decoration: const InputDecoration(
                labelText: 'Customer / Buyer Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter customer name' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'What was sold? (e.g. 20L milk, 3 hens)',
                prefixIcon: Icon(Icons.label_outline),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 1,
            ),
            const SizedBox(height: 24),

            // ── Section: Amount ────────────────────────────────────────────
            _SectionLabel(label: 'Amount'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Amount (KES)',
                prefixIcon: Icon(Icons.payments_outlined),
                prefixText: 'KES  ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter amount';
                final n = double.tryParse(v);
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // ── Section: Payment Method ────────────────────────────────────
            _SectionLabel(label: 'Payment Method'),
            const SizedBox(height: 10),
            _PaymentMethodSelector(
              selected: _paymentMethod,
              onChanged: (m) => setState(() => _paymentMethod = m),
            ),

            // M-PESA code field (conditional)
            if (_paymentMethod == PaymentMethod.MPESA) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _mpesaCodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'M-PESA Confirmation Code (optional)',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                  hintText: 'e.g. RCX4D9ABCD',
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ],
            const SizedBox(height: 24),

            // ── Section: KRA Certification ─────────────────────────────────
            _SectionLabel(label: 'KRA / eTIMS'),
            const SizedBox(height: 10),
            _KraToggleCard(
              isKraCertified: _isKraCertified,
              onToggle: (v) => setState(() => _isKraCertified = v),
              kraRefController: _kraRefCtrl,
            ),
            const SizedBox(height: 32),

            // ── Submit Button ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5,
                        ),
                      )
                    : const Text('Record Sale'),
              ),
            ),

            const SizedBox(height: 12),
            Center(
              child: Text(
                'Saves offline — syncs to cloud automatically',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sales History Tab ─────────────────────────────────────────────────────────

class _SalesHistoryTab extends StatefulWidget {
  const _SalesHistoryTab();

  @override
  State<_SalesHistoryTab> createState() => _SalesHistoryTabState();
}

class _SalesHistoryTabState extends State<_SalesHistoryTab> {
  final _repo = LedgerRepository();
  late Future<List<LedgerEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getRecentLedger();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<LedgerEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data
            ?.where((e) => e.type == LedgerType.SALE)
            .toList() ?? [];

        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined, size: 56, color: scheme.outlineVariant),
                const SizedBox(height: 12),
                Text(
                  'No sales recorded yet',
                  style: TextStyle(color: scheme.outline, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap "Record Sale" to get started.',
                  style: TextStyle(color: scheme.outlineVariant, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _SaleTile(entry: entries[i]),
        );
      },
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.primary.withValues(),
      ),
    );
  }
}

class _PaymentMethodSelector extends StatelessWidget {
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;

  const _PaymentMethodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final methods = [
      (PaymentMethod.MPESA,  'M-PESA',  Icons.phone_android),
      (PaymentMethod.CASH,   'Cash',    Icons.money),
      (PaymentMethod.BANK,   'Bank',    Icons.account_balance_outlined),
    ];

    return Row(
      children: methods.map((m) {
        final (method, label, icon) = m;
        final isSelected = selected == method;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(method),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? scheme.primary.withValues() : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? scheme.primary : const Color(0xFFDDE5DA),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(icon,
                    size: 20,
                    color: isSelected ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? scheme.primary : scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _KraToggleCard extends StatelessWidget {
  final bool isKraCertified;
  final ValueChanged<bool> onToggle;
  final TextEditingController kraRefController;

  const _KraToggleCard({
    required this.isKraCertified,
    required this.onToggle,
    required this.kraRefController,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isKraCertified
              ? scheme.primary.withValues()
              : const Color(0xFFDDE5DA),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined,
                color: isKraCertified ? scheme.primary : scheme.outline,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('KRA Certified',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isKraCertified ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    Text('Has an official eTIMS receipt number',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isKraCertified,
                onChanged: onToggle,
                activeThumbColor: scheme.primary,
              ),
            ],
          ),
          if (isKraCertified) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: kraRefController,
              decoration: const InputDecoration(
                labelText: 'eTIMS / KRA Reference Number',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (v) => (isKraCertified && (v == null || v.trim().isEmpty))
                  ? 'Enter KRA reference' : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String message;
  const _SuccessBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D6A4F).withValues(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D6A4F).withValues()),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF2D6A4F), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF2D6A4F),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  final LedgerEntry entry;
  const _SaleTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPending = entry.status == LedgerStatus.pending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.receipt_long, color: scheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KES ${entry.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  Text(
                    entry.createdAt.toString().substring(0, 16),
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ),
            ),
            // Sync status chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPending
                    ? Colors.orange.withValues()
                    : scheme.primary.withValues(),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isPending ? 'Pending sync' : 'Synced',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isPending ? Colors.orange.shade800 : scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}