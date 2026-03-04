import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/ledger_entry.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../services/sync_service.dart';
import '../../services/session_manager.dart';

const _uuid = Uuid();

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
                Text('Transactions', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: -0.5)),
                Text('Sales & Purchases', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.outline)),
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
                  tabs: const [
                    Tab(text: 'Record Sale'),
                    Tab(text: 'Record Purchase'),
                    Tab(text: 'History'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _TransactionForm(type: TransactionType.sale, onSuccess: () => _tabController.animateTo(2)),
            _TransactionForm(type: TransactionType.purchase, onSuccess: () => _tabController.animateTo(2)),
            const _HistoryTab(),
          ],
        ),
      ),
    );
  }
}

// ── Shared Transaction Form (Sale + Purchase) ─────────────────────────────────

class _TransactionForm extends StatefulWidget {
  final TransactionType type;
  final VoidCallback onSuccess;
  const _TransactionForm({required this.type, required this.onSuccess});
  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  final _formKey       = GlobalKey<FormState>();
  final _repo          = LedgerRepository();
  final _nameCtrl      = TextEditingController();
  final _amountCtrl    = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _mpesaCodeCtrl = TextEditingController();
  final _kraRefCtrl    = TextEditingController();

  PaymentMethod _paymentMethod = PaymentMethod.MPESA;
  bool _isKraCertified = false;
  bool _isSaving = false;
  String? _successMessage;

  bool get _isSale => widget.type == TransactionType.sale;

  @override
  void dispose() {
    _nameCtrl.dispose(); _amountCtrl.dispose(); _descCtrl.dispose();
    _mpesaCodeCtrl.dispose(); _kraRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSaving = true; _successMessage = null; });

    try {
      final amount = double.parse(_amountCtrl.text.trim());
      final sourceId = _uuid.v4();
      final txnId = _uuid.v4();
      final userId = SessionManager.instance.currentUserId;

      final metadata = <String, dynamic>{
        'description': _descCtrl.text.trim(),
        if (!_isSale) 'supplier': _nameCtrl.text.trim(),
        if (_paymentMethod == PaymentMethod.MPESA && _mpesaCodeCtrl.text.isNotEmpty)
          'mpesa_code': _mpesaCodeCtrl.text.trim().toUpperCase(),
      };

      final financial = Financial(
        transactionId: txnId,
        transactionType: widget.type,
        customerSupplierName: _nameCtrl.text.trim(),
        paymentMethod: _paymentMethod,
        amount: amount,
        description: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
        isKraCertified: _isKraCertified,
        kraReference: _isKraCertified ? _kraRefCtrl.text.trim() : null,
        createdBy: userId,
        createdAt: DateTime.now(),
      );

      if (_isSale) {
        await _repo.recordSale(sourceId: sourceId, amount: amount, financial: financial, metadata: metadata);
      } else {
        await _repo.recordPurchase(sourceId: sourceId, amount: amount, financial: financial, metadata: metadata);
      }

      SyncService().processQueue();

      setState(() => _successMessage = '${_isSale ? 'Sale' : 'Purchase'} of KES ${_amountCtrl.text} recorded ✓');
      _resetForm();

      // Jump to history after short delay
      await Future.delayed(const Duration(milliseconds: 800));
      widget.onSuccess();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Saved locally. Will sync when online.'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _nameCtrl.clear(); _amountCtrl.clear(); _descCtrl.clear();
    _mpesaCodeCtrl.clear(); _kraRefCtrl.clear();
    setState(() { _paymentMethod = PaymentMethod.MPESA; _isKraCertified = false; });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = _isSale ? const Color(0xFF2D6A4F) : const Color(0xFF9B2226);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          // Type banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(_isSale ? Icons.trending_up : Icons.trending_down, color: accentColor, size: 18),
              const SizedBox(width: 10),
              Text(
                _isSale ? 'Recording income from a sale' : 'Recording an expense / purchase',
                style: TextStyle(color: accentColor, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Who
          _SectionLabel(label: _isSale ? 'Customer Details' : 'Supplier Details'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: _isSale ? 'Customer / Buyer Name' : 'Supplier / Vendor Name',
              prefixIcon: const Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descCtrl,
            decoration: InputDecoration(
              labelText: _isSale ? 'What was sold? (e.g. 20L milk)' : 'What was purchased? (e.g. Dairy meal 50kg)',
              prefixIcon: const Icon(Icons.label_outline),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 24),

          // Amount
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
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter amount';
              if ((double.tryParse(v) ?? 0) <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Payment method
          _SectionLabel(label: 'Payment Method'),
          const SizedBox(height: 10),
          _PaymentMethodSelector(selected: _paymentMethod, onChanged: (m) => setState(() => _paymentMethod = m), accentColor: accentColor),

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

          // KRA
          _SectionLabel(label: 'KRA / eTIMS'),
          const SizedBox(height: 10),
          _KraToggleCard(isKraCertified: _isKraCertified, onToggle: (v) => setState(() => _isKraCertified = v), kraRefController: _kraRefCtrl),
          const SizedBox(height: 32),

          // Success banner
          if (_successMessage != null) ...[
            _SuccessBanner(message: _successMessage!, color: accentColor),
            const SizedBox(height: 16),
          ],

          // Submit
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Text(_isSale ? 'Record Sale' : 'Record Purchase',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: Text('Saves offline · syncs to cloud automatically',
              style: TextStyle(fontSize: 11, color: scheme.outline, fontWeight: FontWeight.w500))),
        ]),
      ),
    );
  }
}

// ── History Tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _repo = LedgerRepository();
  late Future<List<Financial>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getRecentFinancials();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<Financial>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final records = snap.data ?? [];
        if (records.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Text('No transactions yet', style: TextStyle(color: scheme.outline, fontWeight: FontWeight.w600)),
          ]));
        }

        // Summary totals
        final totalSales = records.where((r) => r.transactionType == TransactionType.sale).fold(0.0, (s, r) => s + r.amount);
        final totalPurchases = records.where((r) => r.transactionType == TransactionType.purchase).fold(0.0, (s, r) => s + r.amount);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            // Summary row
            Row(children: [
              Expanded(child: _SummaryTile('Total Sales', totalSales, Icons.trending_up, const Color(0xFF2D6A4F))),
              const SizedBox(width: 12),
              Expanded(child: _SummaryTile('Total Purchases', totalPurchases, Icons.trending_down, const Color(0xFF9B2226))),
            ]),
            const SizedBox(height: 20),
            const _SectionLabel(label: 'All Transactions'),
            const SizedBox(height: 10),
            ...records.map((r) => _TxnTile(record: r)),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  const _SummaryTile(this.label, this.amount, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text('KES ${amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8))),
        ]),
      );
}

class _TxnTile extends StatelessWidget {
  final Financial record;
  const _TxnTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final isSale = record.transactionType == TransactionType.sale;
    final color = isSale ? const Color(0xFF2D6A4F) : const Color(0xFF9B2226);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8E8E0)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(isSale ? Icons.trending_up : Icons.trending_down, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(record.customerSupplierName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          if (record.description != null && record.description!.isNotEmpty)
            Text(record.description!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            _Tag(record.paymentMethod.name, Colors.grey.shade200, Colors.grey.shade700),
            const SizedBox(width: 6),
            if (record.isKraCertified) _Tag('KRA ✓', const Color(0xFFD8F3DC), const Color(0xFF2D6A4F)),
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${isSale ? '+' : '-'}KES ${record.amount.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color),
          ),
          Text(record.createdAt.toString().substring(0, 10),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ]),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Tag(this.text, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label.toUpperCase(),
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)));
}

class _PaymentMethodSelector extends StatelessWidget {
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;
  final Color accentColor;
  const _PaymentMethodSelector({required this.selected, required this.onChanged, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final methods = [(PaymentMethod.MPESA, 'M-PESA', Icons.phone_android), (PaymentMethod.CASH, 'Cash', Icons.money), (PaymentMethod.BANK, 'Bank', Icons.account_balance_outlined)];
    return Row(
      children: methods.map((m) {
        final (method, label, icon) = m;
        final isSel = selected == method;
        return Expanded(child: GestureDetector(
          onTap: () => onChanged(method),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSel ? accentColor.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSel ? accentColor : const Color(0xFFDDE5DA), width: isSel ? 2 : 1),
            ),
            child: Column(children: [
              Icon(icon, size: 20, color: isSel ? accentColor : Colors.grey),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: isSel ? accentColor : Colors.grey)),
            ]),
          ),
        ));
      }).toList(),
    );
  }
}

class _KraToggleCard extends StatelessWidget {
  final bool isKraCertified;
  final ValueChanged<bool> onToggle;
  final TextEditingController kraRefController;
  const _KraToggleCard({required this.isKraCertified, required this.onToggle, required this.kraRefController});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isKraCertified ? scheme.primary.withValues(alpha: 0.4) : const Color(0xFFDDE5DA)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.verified_outlined, color: isKraCertified ? scheme.primary : scheme.outline, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('KRA Certified', style: TextStyle(fontWeight: FontWeight.w700, color: isKraCertified ? scheme.primary : scheme.onSurface)),
            Text('Has an official eTIMS receipt number', style: TextStyle(fontSize: 11, color: scheme.outline)),
          ])),
          Switch.adaptive(value: isKraCertified, onChanged: onToggle, activeThumbColor: scheme.primary),
        ]),
        if (isKraCertified) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: kraRefController,
            decoration: const InputDecoration(labelText: 'eTIMS / KRA Reference Number', prefixIcon: Icon(Icons.tag_outlined)),
            textCapitalization: TextCapitalization.characters,
            validator: (v) => (isKraCertified && (v == null || v.trim().isEmpty)) ? 'Enter KRA reference' : null,
          ),
        ],
      ]),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String message;
  final Color color;
  const _SuccessBanner({required this.message, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(children: [
          Icon(Icons.check_circle, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      );
}