import 'enums.dart';

class PartialPayment {
  final String paymentId;
  final String transactionId; // FK → financials.transaction_id
  final double amount;
  final PaymentMethod method;
  final String? mpesaReceipt;
  final String? checkoutRequestId;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;

  const PartialPayment({
    required this.paymentId,
    required this.transactionId,
    required this.amount,
    required this.method,
    this.mpesaReceipt,
    this.checkoutRequestId,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'payment_id':           paymentId,
        'transaction_id':       transactionId,
        'amount':               amount,
        'method':               method.name,
        'mpesa_receipt':        mpesaReceipt,
        'checkout_request_id':  checkoutRequestId,
        'notes':                notes,
        'created_by':           createdBy,
        'created_at':           createdAt.toIso8601String(),
      };

  factory PartialPayment.fromMap(Map<String, dynamic> map) => PartialPayment(
        paymentId:          map['payment_id'] as String,
        transactionId:      map['transaction_id'] as String,
        amount:             (map['amount'] as num).toDouble(),
        method:             PaymentMethod.values.byName(map['method'] as String),
        mpesaReceipt:       map['mpesa_receipt'] as String?,
        checkoutRequestId:  map['checkout_request_id'] as String?,
        notes:              map['notes'] as String?,
        createdBy:          map['created_by'] as String? ?? 'unknown',
        createdAt:          DateTime.parse(map['created_at'] as String),
      );
}