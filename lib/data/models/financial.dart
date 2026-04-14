// lib/data/models/financial.dart

import 'enums.dart';

class Financial {
  final String transactionId;
  final TransactionType transactionType;
  final String customerSupplierName;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final double amount;
  final double amountPaid;
  final String? description;
  final bool isKraCertified;
  final String? kraReference;
  final String? checkoutRequestId;
  final String? mpesaReceipt;
  final String? eventId;
  final String createdBy;
  final DateTime createdAt;

  double get amountOutstanding => (amount - amountPaid).clamp(0, double.infinity);
  bool   get isFullyPaid       => amountOutstanding == 0;
  bool   get hasPartialPayment => amountPaid > 0 && !isFullyPaid;

  const Financial({
    required this.transactionId,
    required this.transactionType,
    required this.customerSupplierName,
    required this.paymentMethod,
    this.paymentStatus = PaymentStatus.paid,
    required this.amount,
    this.amountPaid = 0.0,
    this.description,
    this.isKraCertified = false,
    this.kraReference,
    this.checkoutRequestId,
    this.mpesaReceipt,
    this.eventId,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'transaction_id':         transactionId,
        'transaction_type':       transactionType.name,
        'customer_supplier_name': customerSupplierName,
        'payment_method':         paymentMethod.name,
        'payment_status':         paymentStatus.name,
        'amount':                 amount,
        'amount_paid':            amountPaid,
        'description':            description,
        'is_kra_certified':       isKraCertified ? 1 : 0,
        'kra_reference':          kraReference,
        'checkout_request_id':    checkoutRequestId,
        'mpesa_receipt':          mpesaReceipt,
        'event_id':               eventId,
        'created_by':             createdBy,
        'created_at':             createdAt.toIso8601String(),
      };

  factory Financial.fromMap(Map<String, dynamic> map) => Financial(
        transactionId:        map['transaction_id'] as String,
        transactionType:      TransactionType.values
            .byName((map['transaction_type'] as String?)?.toLowerCase() ?? 'sale'),
        customerSupplierName: map['customer_supplier_name'] as String,
        paymentMethod:        PaymentMethod.values
            .byName((map['payment_method'] as String).toLowerCase()),
        paymentStatus:        PaymentStatus.values
            .byName((map['payment_status'] as String?)?.toLowerCase() ?? 'paid'),
        amount:               (map['amount'] as num).toDouble(),
        amountPaid:           (map['amount_paid'] as num?)?.toDouble() ?? 0.0,
        description:          map['description'] as String?,
        isKraCertified:       (map['is_kra_certified'] as int?) == 1,
        kraReference:         map['kra_reference'] as String?,
        checkoutRequestId:    map['checkout_request_id'] as String?,
        mpesaReceipt:         map['mpesa_receipt'] as String?,
        eventId:              map['event_id'] as String?,
        createdBy:            map['created_by'] as String? ?? 'unknown',
        createdAt:            DateTime.parse(map['created_at'] as String).toUtc(),
      );

  Financial copyWith({
    String?        eventId,
    String?        createdBy,
    PaymentStatus? paymentStatus,
    String?        checkoutRequestId,
    String?        mpesaReceipt,
    double?        amountPaid,
  }) => Financial(
        transactionId:        transactionId,
        transactionType:      transactionType,
        customerSupplierName: customerSupplierName,
        paymentMethod:        paymentMethod,
        paymentStatus:        paymentStatus      ?? this.paymentStatus,
        amount:               amount,
        amountPaid:           amountPaid         ?? this.amountPaid,
        description:          description,
        isKraCertified:       isKraCertified,
        kraReference:         kraReference,
        checkoutRequestId:    checkoutRequestId  ?? this.checkoutRequestId,
        mpesaReceipt:         mpesaReceipt       ?? this.mpesaReceipt,
        eventId:              eventId            ?? this.eventId,
        createdBy:            createdBy          ?? this.createdBy,
        createdAt:            createdAt,
      );
}