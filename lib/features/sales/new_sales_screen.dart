import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../data/models/ledger_entry.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../services/mpesa_listener_service.dart';
import '../../services/session_manager.dart';
import '../../shared/app_widgets.dart';
import 'checkout_sheet.dart';

const _uuid = Uuid();

// ── Sales Screen ──────────────────────────────────────────────────────────────
/// Bottom-nav Sales tab. Three tabs:
///   1. New Sale   — form to create a sale (cash, M-PESA STK, manual receipt, credit)
///   2. Purchases  — form to record expenses
///   3. History    — full transaction list with outstanding balances highlighted

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});
  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 56),
              title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transactions',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                            letterSpacing: -0.5)),
                    Text('Sales & Purchases',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: scheme.outline)),
                  ]),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: scheme.outline.withValues(alpha: 0.15)))),
                child: TabBar(
                  controller: _tabs,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.outline,
                  indicatorColor: scheme.primary,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: const [
                    Tab(text: 'New Sale'),
                    Tab(text: 'Purchase'),
                    Tab(text: 'History'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _TransactionForm(
                type: TransactionType.sale,
                onSuccess: () => _tabs.animateTo(2)),
            _TransactionForm(
                type: TransactionType.purchase,
                onSuccess: () => _tabs.animateTo(2)),
            _HistoryTab(onRecordPayment: () => _tabs.animateTo(2)),
          ],
        ),
      ),
    );
  }
}

// ── Transaction Form ──────────────────────────────────────────────────────────

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
  final _kraRefCtrl    = TextEditingController();

  PaymentMethod _paymentMethod = PaymentMethod.mpesa;
  bool _isKraCertified = false;
  bool _isSaving       = false;
  String? _successMessage;

  bool get _isSale => widget.type == TransactionType.sale;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _kraRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSaving = true; _successMessage = null; });

    try {
      final amount   = double.parse(_amountCtrl.text.trim());
      final sourceId = _uuid.v4();
      final txnId    = _uuid.v4();

      // For sale: open the full CheckoutSheet which handles payment method
      // selection and M-PESA STK natively.
      if (_isSale) {
        final completed = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => CheckoutSheet(
            totalAmount:   amount,
            customerName:  _nameCtrl.text.trim(),
            description:   _descCtrl.text.trim(),
            transactionId: txnId,
            isKraCertified: _isKraCertified,
            kraReference:  _isKraCertified ? _kraRefCtrl.text.trim() : null,
          ),
        );
        if (completed == true && mounted) {
          _resetForm();
          setState(() => _successMessage = 'Sale recorded ✓');
          await Future.delayed(const Duration(milliseconds: 600));
          widget.onSuccess();
        }
        return;
      }

      // For purchases: record directly (no STK push needed)
      final financial = Financial(
        transactionId:        txnId,
        transactionType:      TransactionType.purchase,
        customerSupplierName: _nameCtrl.text.trim(),
        paymentMethod:        _paymentMethod,
        paymentStatus:        PaymentStatus.paid,
        amount:               amount,
        amountPaid:           amount,
        description:          _descCtrl.text.trim().isNotEmpty
            ? _descCtrl.text.trim()
            : null,
        isKraCertified:       _isKraCertified,
        kraReference:         _isKraCertified ? _kraRefCtrl.text.trim() : null,
        createdBy:            SessionManager.instance.currentUserId,
        createdAt:            DateTime.now(),
      );

      await _repo.recordPurchase(
        sourceId: sourceId,
        amount:   amount,
        financial: financial,
      );

      if (mounted) {
        _resetForm();
        setState(() => _successMessage =
            'Purchase of KES ${amount.toStringAsFixed(0)} recorded ✓');
        await Future.delayed(const Duration(milliseconds: 600));
        widget.onSuccess();
      }
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
    _nameCtrl.clear();
    _amountCtrl.clear();
    _descCtrl.clear();
    _kraRefCtrl.clear();
    setState(() {
      _paymentMethod  = PaymentMethod.mpesa;
      _isKraCertified = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme      = Theme.of(context).colorScheme;
    final accentColor = _isSale
        ? const Color(0xFF2D6A4F)
        : const Color(0xFF9B2226);

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
              Icon(_isSale ? Icons.trending_up : Icons.trending_down,
                  color: accentColor, size: 18),
              const SizedBox(width: 10),
              Text(
                _isSale
                    ? 'Recording income from a sale'
                    : 'Recording an expense / purchase',
                style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Who
          SectionLabel(_isSale ? 'Customer Details' : 'Supplier Details'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: _isSale ? 'Customer / Buyer Name' : 'Supplier / Vendor Name',
              prefixIcon: const Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'This field is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descCtrl,
            decoration: InputDecoration(
              labelText: _isSale
                  ? 'What was sold? (e.g. 20L milk)'
                  : 'What was purchased? (e.g. Dairy meal 50kg)',
              prefixIcon: const Icon(Icons.label_outline),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 24),

          // Amount
          const SectionLabel('Amount'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Amount (KES)',
              prefixIcon: Icon(Icons.payments_outlined),
              prefixText: 'KES  ',
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
            ],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter amount';
              if ((double.tryParse(v) ?? 0) <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Payment method (purchases only — sales go via CheckoutSheet)
          if (!_isSale) ...[ 
            const SectionLabel('Payment Method'),
            const SizedBox(height: 10),
            _PaymentMethodSelector(
              selected: _paymentMethod,
              onChanged: (m) => setState(() => _paymentMethod = m),
              accentColor: accentColor,
            ),
            const SizedBox(height: 24),
          ],

          // KRA
          const SectionLabel('KRA / eTIMS'),
          const SizedBox(height: 10),
          _KraToggleCard(
            isKraCertified: _isKraCertified,
            onToggle: (v) => setState(() => _isKraCertified = v),
            kraRefController: _kraRefCtrl,
          ),
          const SizedBox(height: 32),

          // Success banner
          if (_successMessage != null) ...[
            _SuccessBanner(message: _successMessage!, color: accentColor),
            const SizedBox(height: 16),
          ],

          // Submit
          ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text(
                    _isSale ? 'Choose Payment Method →' : 'Record Purchase',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Saves offline · syncs to cloud automatically',
              style: TextStyle(
                  fontSize: 11,
                  color: scheme.outline,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── History Tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends StatefulWidget {
  final VoidCallback onRecordPayment;
  const _HistoryTab({required this.onRecordPayment});
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _repo = LedgerRepository();
  late Future<List<Financial>> _future;
  StreamSubscription<MpesaConfirmation>? _mpesaSub;

  @override
  void initState() {
    super.initState();
    _future = _repo.getRecentFinancials();
    // Auto-refresh when an STK payment is confirmed (Realtime or poll)
    _mpesaSub = MpesaListenerService.instance.confirmations.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _mpesaSub?.cancel();
    super.dispose();
  }

  void _load() {
    final next = _repo.getRecentFinancials();
    setState(() => _future = next);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Financial>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFF2D6A4F)));
        }
        final records = snap.data ?? [];
        if (records.isEmpty) {
          return AppEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions yet',
            subtitle:
                'Record a sale or purchase and it will appear here.',
          );
        }

        final sales     = records.where((r) => r.transactionType == TransactionType.sale);
        final purchases = records.where((r) => r.transactionType == TransactionType.purchase);
        final totalSales     = sales.fold(0.0, (s, r) => s + r.amount);
        final totalPurchases = purchases.fold(0.0, (s, r) => s + r.amount);
        final outstanding    = sales.fold(0.0, (s, r) => s + r.amountOutstanding);

        return RefreshIndicator(
          color: const Color(0xFF2D6A4F),
          onRefresh: () async => _load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              // Summary row
              Row(children: [
                Expanded(
                    child: _SummaryTile('Total Sales', totalSales,
                        Icons.trending_up, const Color(0xFF2D6A4F))),
                const SizedBox(width: 10),
                Expanded(
                    child: _SummaryTile('Purchases', totalPurchases,
                        Icons.trending_down, const Color(0xFF9B2226))),
                const SizedBox(width: 10),
                Expanded(
                    child: _SummaryTile('Outstanding', outstanding,
                        Icons.hourglass_top_outlined, Colors.orange.shade700,
                        highlight: outstanding > 0)),
              ]),
              const SizedBox(height: 20),

              // Outstanding section (if any)
              if (outstanding > 0) ...[
                const SectionLabel('Awaiting Payment'),
                const SizedBox(height: 10),
                ...records
                    .where((r) =>
                        r.transactionType == TransactionType.sale &&
                        !r.isFullyPaid)
                    .map((r) => _TxnTile(
                          record: r,
                          repo: _repo,
                          onPaymentRecorded: _load,
                        )),
                const SizedBox(height: 20),
              ],

              const SectionLabel('All Transactions'),
              const SizedBox(height: 10),
              ...records.map((r) => _TxnTile(
                    record: r,
                    repo: _repo,
                    onPaymentRecorded: _load,
                  )),
            ],
          ),
        );
      },
    );
  }
}

// ── Transaction Tile ──────────────────────────────────────────────────────────

class _TxnTile extends StatelessWidget {
  final Financial record;
  final LedgerRepository repo;
  final VoidCallback onPaymentRecorded;
  const _TxnTile({
    required this.record,
    required this.repo,
    required this.onPaymentRecorded,
  });

  @override
  Widget build(BuildContext context) {
    final isSale = record.transactionType == TransactionType.sale;
    final color  = isSale ? const Color(0xFF2D6A4F) : const Color(0xFF9B2226);
    final hasOutstanding = record.amountOutstanding > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: hasOutstanding
                ? Colors.orange.shade200
                : const Color(0xFFD8E8E0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isSale && hasOutstanding
            ? () => _openPaymentSheet(context)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    isSale ? Icons.trending_up : Icons.trending_down,
                    color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(record.customerSupplierName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  if (record.description != null &&
                      record.description!.isNotEmpty)
                    Text(record.description!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    _Tag(record.paymentMethod.name.toUpperCase(),
                        Colors.grey.shade100, Colors.grey.shade700),
                    const SizedBox(width: 5),
                    if (record.isKraCertified)
                      const _Tag('KRA ✓', Color(0xFFD8F3DC),
                          Color(0xFF2D6A4F)),
                    if (record.hasPartialPayment)
                      const _Tag('PARTIAL', Color(0xFFFFF3CD),
                          Color(0xFFB45309)),
                  ]),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  '${isSale ? '+' : '-'}KES ${record.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: color),
                ),
                Text(
                  record.createdAt.toString().substring(0, 10),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                ),
              ]),
            ]),

            // Outstanding balance row
            if (hasOutstanding && isSale) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.hourglass_top_outlined,
                      size: 13, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Text(
                    record.amountPaid > 0
                        ? 'Paid KES ${record.amountPaid.toStringAsFixed(0)} · '
                            'Owes KES ${record.amountOutstanding.toStringAsFixed(0)}'
                        : 'Unpaid · KES ${record.amountOutstanding.toStringAsFixed(0)} outstanding',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800),
                  ),
                  const Spacer(),
                  Text('Tap to collect',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade600)),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  void _openPaymentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordPaymentSheet(
        record: record,
        repo: repo,
        onSaved: onPaymentRecorded,
      ),
    );
  }
}

// ── Record Payment Sheet ──────────────────────────────────────────────────────
/// Shown when tapping an outstanding sale tile. Lets the user record one
/// instalment (full or partial) against the existing sale record.

class _RecordPaymentSheet extends StatefulWidget {
  final Financial record;
  final LedgerRepository repo;
  final VoidCallback onSaved;
  const _RecordPaymentSheet(
      {required this.record, required this.repo, required this.onSaved});
  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  final _amountCtrl  = TextEditingController();
  final _receiptCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.mpesa;
  bool _saving = false;
  late Future<List<PartialPayment>> _paymentsFuture;

  @override
  void initState() {
    super.initState();
    // Pre-fill with outstanding amount
    _amountCtrl.text =
        widget.record.amountOutstanding.toStringAsFixed(0);
    _paymentsFuture =
        widget.repo.getPaymentsForTransaction(widget.record.transactionId);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _receiptCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    if (amount > widget.record.amountOutstanding) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Amount exceeds outstanding balance')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.addPartialPayment(
        transactionId: widget.record.transactionId,
        amount:        amount,
        method:        _method,
        mpesaReceipt:  _receiptCtrl.text.trim().isNotEmpty
            ? _receiptCtrl.text.trim().toUpperCase()
            : null,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'KES ${amount.toStringAsFixed(0)} payment recorded ✓'),
          backgroundColor: const Color(0xFF2D6A4F),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Handle
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          // Header
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Record Payment',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(r.customerSupplierName,
                    style: const TextStyle(
                        color: Color(0xFF2D6A4F),
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('KES ${r.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1B4332))),
              Text('Total sale',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
            ]),
          ]),
          const SizedBox(height: 16),

          // Progress bar
          _PaymentProgress(record: r),
          const SizedBox(height: 20),

          // Payment history
          FutureBuilder<List<PartialPayment>>(
            future: _paymentsFuture,
            builder: (_, snap) {
              final payments = snap.data ?? [];
              if (payments.isEmpty) return const SizedBox.shrink();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Payment History'),
                    const SizedBox(height: 8),
                    ...payments.map((p) => _PaymentHistoryTile(payment: p)),
                    const SizedBox(height: 16),
                  ]);
            },
          ),

          const SectionLabel('New Payment'),
          const SizedBox(height: 12),

          // Amount
          TextFormField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
            ],
            decoration: InputDecoration(
              labelText: 'Amount to collect (KES)',
              hintText:
                  'Max: KES ${r.amountOutstanding.toStringAsFixed(0)}',
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 12),

          // Method
          _PaymentMethodSelector(
            selected: _method,
            onChanged: (m) => setState(() => _method = m),
            accentColor: const Color(0xFF2D6A4F),
          ),

          // M-PESA receipt (optional)
          if (_method == PaymentMethod.mpesa) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _receiptCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'M-PESA Receipt (optional)',
                hintText: 'e.g. RCX4D9ABCD',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
            ),
          ],
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
                : const Text('Save Payment',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ── Payment Progress Bar ──────────────────────────────────────────────────────

class _PaymentProgress extends StatelessWidget {
  final Financial record;
  const _PaymentProgress({required this.record});
  @override
  Widget build(BuildContext context) {
    final pct = record.amount == 0
        ? 0.0
        : (record.amountPaid / record.amount).clamp(0.0, 1.0);
    final color = pct >= 1.0
        ? const Color(0xFF2D6A4F)
        : (pct > 0 ? Colors.orange : Colors.grey.shade300);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(
          'KES ${record.amountPaid.toStringAsFixed(0)} collected',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color),
        ),
        const Spacer(),
        Text(
          'KES ${record.amountOutstanding.toStringAsFixed(0)} outstanding',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct,
          minHeight: 8,
          backgroundColor: Colors.grey.shade100,
          color: color,
        ),
      ),
    ]);
  }
}

// ── Payment History Tile ──────────────────────────────────────────────────────

class _PaymentHistoryTile extends StatelessWidget {
  final PartialPayment payment;
  const _PaymentHistoryTile({required this.payment});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E8E0)),
      ),
      child: Row(children: [
        Icon(Icons.check_circle_outline,
            size: 16, color: const Color(0xFF2D6A4F)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              'KES ${payment.amount.toStringAsFixed(0)} via ${payment.method.name.toUpperCase()}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (payment.mpesaReceipt != null)
              Text(payment.mpesaReceipt!,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ),
        Text(
          payment.createdAt.toString().substring(0, 10),
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
        ),
      ]),
    );
  }
}

// ── Summary Tile ──────────────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  final bool highlight;
  const _SummaryTile(this.label, this.amount, this.icon, this.color,
      {this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: highlight
              ? color.withValues(alpha: 0.1)
              : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 4),
          Text(formatKes(amount),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
        ]),
      );
}

// ── Shared Widgets (local to sales feature) ───────────────────────────────────

class _Tag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Tag(this.text, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _PaymentMethodSelector extends StatelessWidget {
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;
  final Color accentColor;
  const _PaymentMethodSelector(
      {required this.selected,
      required this.onChanged,
      required this.accentColor});

  @override
  Widget build(BuildContext context) {
    const methods = [
      (PaymentMethod.mpesa, 'M-PESA', Icons.phone_android),
      (PaymentMethod.cash, 'Cash', Icons.money),
      (PaymentMethod.bank, 'Bank', Icons.account_balance_outlined),
    ];
    return Row(
      children: methods.map((m) {
        final (method, label, icon) = m;
        final isSel = selected == method;
        return Expanded(
            child: GestureDetector(
          onTap: () => onChanged(method),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSel ? accentColor.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isSel ? accentColor : const Color(0xFFDDE5DA),
                  width: isSel ? 2 : 1),
            ),
            child: Column(children: [
              Icon(icon, size: 20, color: isSel ? accentColor : Colors.grey),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel ? accentColor : Colors.grey)),
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
  const _KraToggleCard(
      {required this.isKraCertified,
      required this.onToggle,
      required this.kraRefController});

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
                ? scheme.primary.withValues(alpha: 0.4)
                : const Color(0xFFDDE5DA)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.verified_outlined,
              color: isKraCertified ? scheme.primary : scheme.outline,
              size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text('KRA Certified',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isKraCertified
                        ? scheme.primary
                        : scheme.onSurface)),
            Text('Has an official eTIMS receipt number',
                style:
                    TextStyle(fontSize: 11, color: scheme.outline)),
          ])),
          Switch.adaptive(
              value: isKraCertified,
              onChanged: onToggle,
              activeThumbColor: scheme.primary),
        ]),
        if (isKraCertified) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: kraRefController,
            decoration: const InputDecoration(
                labelText: 'eTIMS / KRA Reference Number',
                prefixIcon: Icon(Icons.tag_outlined)),
            textCapitalization: TextCapitalization.characters,
            validator: (v) =>
                (isKraCertified && (v == null || v.trim().isEmpty))
                    ? 'Enter KRA reference'
                    : null,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(children: [
          Icon(Icons.check_circle, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13))),
        ]),
      );
}