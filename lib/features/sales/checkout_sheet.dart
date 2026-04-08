import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/mpesa_service.dart';
import '../../services/session_manager.dart';

const _uuid = Uuid();

// ── Payment mode ──────────────────────────────────────────────────────────────
enum _CheckoutMode { mpesaStk, mpesaManual, cash, credit }

// ── CheckoutSheet ─────────────────────────────────────────────────────────────
/// Bottom sheet shown after the New Sale form is filled.
/// Handles all payment modes and saves through LedgerRepository (no raw SQL).
///
/// Returns true to the caller on successful save.

class CheckoutSheet extends StatefulWidget {
  final double totalAmount;
  final String customerName;
  final String description;
  final String transactionId;
  final bool isKraCertified;
  final String? kraReference;

  const CheckoutSheet({
    super.key,
    required this.totalAmount,
    required this.customerName,
    required this.description,
    required this.transactionId,
    this.isKraCertified = false,
    this.kraReference,
  });

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  final _repo          = FinanceRepository();
  final _inputCtrl     = TextEditingController();
  _CheckoutMode _mode  = _CheckoutMode.mpesaStk;
  bool _isProcessing   = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  // ── Build Financial + LedgerEntry via repository ───────────────────────────

  Future<void> _confirm() async {
    setState(() => _isProcessing = true);

    try {
      String?       checkoutRequestId;
      String?       mpesaReceipt;
      String?       stkCustomerMessage;
      PaymentMethod paymentMethod;
      PaymentStatus paymentStatus;
      double        amountPaid;

      // ── Mode-specific handling ─────────────────────────────────────────────
      switch (_mode) {
        case _CheckoutMode.mpesaStk:
          paymentMethod = PaymentMethod.mpesa;
          paymentStatus = PaymentStatus.pending; // confirmed via callback
          amountPaid    = 0.0;

          final phone = _inputCtrl.text.trim();
          if (phone.isEmpty) {
            _showError('Enter the customer\'s phone number.');
            return;
          }
          final result = await MpesaService.instance.initiatePayment(
            phone:         phone,
            amount:        widget.totalAmount,
            transactionId: widget.transactionId,
          );
          if (!result.success) {
            _showError(result.error ?? 'M-PESA prompt failed.');
            return;
          }
          checkoutRequestId  = result.checkoutRequestId;
          stkCustomerMessage = result.customerMessage;

        case _CheckoutMode.mpesaManual:
          paymentMethod = PaymentMethod.mpesa;
          paymentStatus = PaymentStatus.paid;
          amountPaid    = widget.totalAmount;
          mpesaReceipt  = _inputCtrl.text.trim().toUpperCase();
          if (mpesaReceipt.isEmpty) {
            _showError('Enter the M-PESA receipt number.');
            return;
          }

        case _CheckoutMode.cash:
          paymentMethod = PaymentMethod.cash;
          paymentStatus = PaymentStatus.paid;
          amountPaid    = widget.totalAmount;

        case _CheckoutMode.credit:
          paymentMethod = PaymentMethod.cash; // method TBD at collection time
          paymentStatus = PaymentStatus.pending;
          amountPaid    = 0.0;
      }

      // ── Persist via LedgerRepository (typed, no raw SQL) ──────────────────
      final financial = Financial(
        transactionId:        widget.transactionId,
        transactionType:      TransactionType.sale,
        customerSupplierName: widget.customerName,
        paymentMethod:        paymentMethod,
        paymentStatus:        paymentStatus,
        amount:               widget.totalAmount,
        amountPaid:           amountPaid,
        description:          widget.description.isNotEmpty
            ? widget.description
            : null,
        isKraCertified:       widget.isKraCertified,
        kraReference:         widget.kraReference,
        checkoutRequestId:    checkoutRequestId,
        mpesaReceipt:         mpesaReceipt,
        createdBy:            SessionManager.instance.currentUserId,
        createdAt:            DateTime.now(),
      );

      await _repo.recordSale(
        sourceId:  _uuid.v4(),
        amount:    widget.totalAmount,
        financial: financial,
        metadata:  {
          'description': widget.description,
          'customer':    widget.customerName,
          'mode':        _mode.name,
        },
      );

      if (!mounted) return;

      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_mode == _CheckoutMode.mpesaStk
            ? stkCustomerMessage ?? 'M-PESA prompt sent!'
            : _mode == _CheckoutMode.credit
                ? 'Sale recorded. KES ${widget.totalAmount.toStringAsFixed(0)} outstanding.'
                : 'Sale of KES ${widget.totalAmount.toStringAsFixed(0)} recorded ✓'),
        backgroundColor: _mode == _CheckoutMode.credit
            ? Colors.orange.shade700
            : const Color(0xFF2D6A4F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      _showError('Failed to save. $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                const Text('Checkout',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                Text(widget.customerName,
                    style: const TextStyle(
                        color: Color(0xFF52796F),
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1B4332),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'KES ${widget.totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          if (widget.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(widget.description,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
          ],
          const SizedBox(height: 24),

          // Mode selector
          const _SheetLabel('Payment Method'),
          const SizedBox(height: 10),
          _ModeSelector(
            selected: _mode,
            onChanged: (m) => setState(() {
              _mode = m;
              _inputCtrl.clear();
            }),
          ),
          const SizedBox(height: 16),

          // Dynamic input
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _modeInput(scheme),
          ),

          const SizedBox(height: 24),

          // Confirm button
          ElevatedButton(
            onPressed: _isProcessing ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D6A4F),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text(_confirmLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _modeInput(ColorScheme scheme) {
    switch (_mode) {
      case _CheckoutMode.mpesaStk:
        return TextFormField(
          controller: _inputCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Customer Phone Number',
            hintText: '07XX XXX XXX or 254...',
            prefixIcon: Icon(Icons.phone_android_outlined),
          ),
        );
      case _CheckoutMode.mpesaManual:
        return TextFormField(
          controller: _inputCtrl,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9a-z]'))
          ],
          decoration: const InputDecoration(
            labelText: 'M-PESA Receipt Number',
            hintText: 'e.g. RCX4D9ABCD',
            prefixIcon: Icon(Icons.confirmation_number_outlined),
          ),
        );
      case _CheckoutMode.cash:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFD8F3DC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF2D6A4F), size: 18),
            const SizedBox(width: 10),
            Text(
              'KES ${widget.totalAmount.toStringAsFixed(0)} received in cash.',
              style: const TextStyle(
                  color: Color(0xFF1B4332), fontWeight: FontWeight.w600),
            ),
          ]),
        );
      case _CheckoutMode.credit:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            Icon(Icons.hourglass_top_outlined,
                color: Colors.orange.shade800, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sale recorded as unpaid. Collect payment later from the History tab.',
                style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          ]),
        );
    }
  }

  String get _confirmLabel => switch (_mode) {
        _CheckoutMode.mpesaStk     => 'Send M-PESA Prompt',
        _CheckoutMode.mpesaManual  => 'Confirm M-PESA Payment',
        _CheckoutMode.cash         => 'Confirm Cash Payment',
        _CheckoutMode.credit       => 'Record as Credit',
      };
}

// ── Mode Selector ─────────────────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  final _CheckoutMode selected;
  final ValueChanged<_CheckoutMode> onChanged;
  const _ModeSelector({required this.selected, required this.onChanged});

  static const _modes = [
    (_CheckoutMode.mpesaStk,    'STK Push',  Icons.phone_android_outlined),
    (_CheckoutMode.mpesaManual, 'M-PESA',    Icons.confirmation_number_outlined),
    (_CheckoutMode.cash,        'Cash',      Icons.money_outlined),
    (_CheckoutMode.credit,      'Credit',    Icons.hourglass_top_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _modes.map((m) {
        final (mode, label, icon) = m;
        final sel = selected == mode;
        final color = mode == _CheckoutMode.credit
            ? Colors.orange.shade700
            : const Color(0xFF2D6A4F);
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? color.withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: sel ? color : const Color(0xFFDDE5DA),
                    width: sel ? 2 : 1),
              ),
              child: Column(children: [
                Icon(icon, size: 18, color: sel ? color : Colors.grey),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight:
                            sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? color : Colors.grey),
                    textAlign: TextAlign.center),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.85)),
      );
}