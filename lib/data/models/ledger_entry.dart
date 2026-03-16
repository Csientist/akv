import 'dart:convert';

// ── Enums (lowerCamelCase per Dart linter) ────────────────────────────────────

enum LedgerType    { sale, purchase, herdUpdate, inventoryAdjust }
enum LedgerStatus  { pending, completed, failed }
enum AssetCategory { livestock, crop }

/// Fixed: was mixed-case { active, SOLD, DECEASED } — now consistent.
enum AssetStatus   { active, sold, deceased }

/// Fixed: was SCREAMING_CASE — now lowerCamelCase.
enum PaymentMethod { mpesa, cash, bank }
enum PaymentStatus { paid, pending, failed }
enum InventoryUnit { kg, litres, bags, pieces, vials }
enum InventoryCategory { feed, medicine, equipment, seed, other }
enum MilkSession   { am, pm, full }

// ── PartialPayment ────────────────────────────────────────────────────────────
/// Represents a single payment instalment against a sale.
/// Stored in the `partial_payments` table (see local_db.dart).

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

// ── LedgerEntry ───────────────────────────────────────────────────────────────

class LedgerEntry {
  final String eventId;
  final LedgerType type;
  final String sourceId;
  final double amount;
  final LedgerStatus status;
  final Map<String, dynamic>? metadata;
  final String createdBy;
  final DateTime createdAt;

  const LedgerEntry({
    required this.eventId,
    required this.type,
    required this.sourceId,
    this.amount = 0.0,
    this.status = LedgerStatus.pending,
    this.metadata,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'event_id':   eventId,
        'type':       type.name,
        'source_id':  sourceId,
        'amount':     amount,
        'status':     status.name,
        'metadata':   metadata != null ? jsonEncode(metadata) : null,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory LedgerEntry.fromMap(Map<String, dynamic> map) => LedgerEntry(
        eventId:   map['event_id'] as String,
        type:      LedgerType.values.byName(map['type'] as String),
        sourceId:  map['source_id'] as String,
        amount:    (map['amount'] as num?)?.toDouble() ?? 0.0,
        status:    LedgerStatus.values.byName(map['status'] as String),
        metadata:  map['metadata'] != null
            ? (map['metadata'] is String
                ? jsonDecode(map['metadata'] as String)
                : map['metadata']) as Map<String, dynamic>
            : null,
        createdBy: map['created_by'] as String? ?? 'unknown',
        createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      );
}

// ── Asset ─────────────────────────────────────────────────────────────────────

class Asset {
  final String assetId;
  final String tagName;
  final AssetCategory category;
  final String breedType;
  final AssetStatus status;
  final double? weightKg;
  final DateTime? dateOfBirth;
  final String? healthNotes;
  final String? lastEventId;
  final String createdBy;
  final DateTime createdAt;

  const Asset({
    required this.assetId,
    required this.tagName,
    required this.category,
    required this.breedType,
    this.status = AssetStatus.active,
    this.weightKg,
    this.dateOfBirth,
    this.healthNotes,
    this.lastEventId,
    required this.createdBy,
    required this.createdAt,
  });

  String get displayAge {
    if (dateOfBirth == null) return 'Unknown age';
    final now = DateTime.now();
    int months = (now.year - dateOfBirth!.year) * 12 +
        (now.month - dateOfBirth!.month);
    if (now.day < dateOfBirth!.day) months--;
    if (months < 0) months = 0;
    if (months < 12) return '${months}mo';
    final years = months ~/ 12;
    final rem   = months % 12;
    return rem > 0 ? '${years}yr ${rem}mo' : '${years}yr';
  }

  int get ageInMonths {
    if (dateOfBirth == null) return 0;
    final now = DateTime.now();
    int months = (now.year - dateOfBirth!.year) * 12 +
        (now.month - dateOfBirth!.month);
    if (now.day < dateOfBirth!.day) months--;
    return months < 0 ? 0 : months;
  }

  Map<String, dynamic> toMap() => {
        'asset_id':      assetId,
        'tag_name':      tagName,
        'category':      category.name,
        'breed_type':    breedType,
        'status':        status.name,
        'weight_kg':     weightKg,
        'date_of_birth': dateOfBirth?.toIso8601String().substring(0, 10),
        'health_notes':  healthNotes,
        'last_event_id': lastEventId,
        'created_by':    createdBy,
        'created_at':    createdAt.toIso8601String(),
      };

  factory Asset.fromMap(Map<String, dynamic> map) => Asset(
        assetId:     map['asset_id'] as String,
        tagName:     map['tag_name'] as String? ?? '',
        category:    AssetCategory.values.byName(map['category'] as String),
        breedType:   map['breed_type'] as String,
        status:      AssetStatus.values.byName(map['status'] as String),
        weightKg:    (map['weight_kg'] as num?)?.toDouble(),
        dateOfBirth: map['date_of_birth'] != null
            ? DateTime.tryParse(map['date_of_birth'] as String) : null,
        healthNotes:  map['health_notes'] as String?,
        lastEventId:  map['last_event_id'] as String?,
        createdBy:    map['created_by'] as String? ?? 'unknown',
        createdAt:    DateTime.parse(map['created_at'] as String),
      );

  Asset copyWith({
    String?       tagName,
    AssetStatus?  status,
    double?       weightKg,
    DateTime?     dateOfBirth,
    String?       healthNotes,
    String?       lastEventId,
    String?       createdBy,
  }) => Asset(
        assetId:     assetId,
        tagName:     tagName     ?? this.tagName,
        category:    category,
        breedType:   breedType,
        status:      status      ?? this.status,
        weightKg:    weightKg    ?? this.weightKg,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        healthNotes: healthNotes ?? this.healthNotes,
        lastEventId: lastEventId ?? this.lastEventId,
        createdBy:   createdBy   ?? this.createdBy,
        createdAt:   createdAt,
      );
}

// ── InventoryItem ─────────────────────────────────────────────────────────────

class InventoryItem {
  final String itemId;
  final String itemName;
  final InventoryCategory category;
  final double quantity;
  final InventoryUnit unit;
  final double reorderLevel;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;

  bool get isLowStock => quantity <= reorderLevel;
  double get stockPercent =>
      reorderLevel == 0 ? 1.0 : (quantity / (reorderLevel * 3)).clamp(0.0, 1.0);

  const InventoryItem({
    required this.itemId,
    required this.itemName,
    this.category = InventoryCategory.feed,
    required this.quantity,
    required this.unit,
    required this.reorderLevel,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'item_id':       itemId,
        'item_name':     itemName,
        'category':      category.name,
        'quantity':      quantity,
        'unit':          unit.name,
        'reorder_level': reorderLevel,
        'notes':         notes,
        'created_by':    createdBy,
        'created_at':    createdAt.toIso8601String(),
      };

  factory InventoryItem.fromMap(Map<String, dynamic> map) => InventoryItem(
        itemId:       map['item_id'] as String,
        itemName:     map['item_name'] as String,
        category:     InventoryCategory.values
            .byName((map['category'] as String?)?.toLowerCase() ?? 'feed'),
        quantity:     (map['quantity'] as num).toDouble(),
        unit:         InventoryUnit.values
            .byName((map['unit'] as String).toLowerCase()),
        reorderLevel: (map['reorder_level'] as num).toDouble(),
        notes:        map['notes'] as String?,
        createdBy:    map['created_by'] as String? ?? 'unknown',
        createdAt:    DateTime.parse(map['created_at'] as String),
      );

  InventoryItem copyWith({
    String?           itemName,
    InventoryCategory? category,
    double?           quantity,
    InventoryUnit?    unit,
    double?           reorderLevel,
    String?           notes,
    String?           createdBy,
  }) => InventoryItem(
        itemId:       itemId,
        itemName:     itemName     ?? this.itemName,
        category:     category     ?? this.category,
        quantity:     quantity     ?? this.quantity,
        unit:         unit         ?? this.unit,
        reorderLevel: reorderLevel ?? this.reorderLevel,
        notes:        notes        ?? this.notes,
        createdBy:    createdBy    ?? this.createdBy,
        createdAt:    createdAt,
      );
}

// ── Financial ─────────────────────────────────────────────────────────────────

enum TransactionType { sale, purchase }

class Financial {
  final String transactionId;
  final TransactionType transactionType;
  final String customerSupplierName;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final double amount;
  /// How much has actually been collected so far (sum of partial_payments).
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

// ── DashboardSummary ──────────────────────────────────────────────────────────

class DashboardSummary {
  final double totalSalesAllTime;
  final double totalPurchasesAllTime;
  final double totalSalesThisMonth;
  final double totalOutstanding;   // NEW: sum of unpaid balances
  final int    livestockCount;
  final int    cropCount;
  final int    lowStockCount;
  final int    pendingSyncCount;
  final List<Financial> recentTransactions;

  const DashboardSummary({
    required this.totalSalesAllTime,
    required this.totalPurchasesAllTime,
    required this.totalSalesThisMonth,
    this.totalOutstanding = 0.0,
    required this.livestockCount,
    required this.cropCount,
    required this.lowStockCount,
    required this.pendingSyncCount,
    required this.recentTransactions,
  });

  double get netPosition => totalSalesAllTime - totalPurchasesAllTime;
}

// ── AssetEvent ────────────────────────────────────────────────────────────────

class AssetEvent {
  final String eventId;
  final String assetId;
  final String eventType;
  final String? notes;
  final Map<String, dynamic>? metadata;
  final DateTime recordedAt;
  final String createdBy;
  final DateTime createdAt;

  const AssetEvent({
    required this.eventId,
    required this.assetId,
    required this.eventType,
    this.notes,
    this.metadata,
    required this.recordedAt,
    required this.createdBy,
    required this.createdAt,
  });

  String get displayLabel {
    const labels = {
      'vaccination':    'Vaccination',
      'deworming':      'Deworming',
      'vetVisit':       'Vet Visit',
      'medication':     'Medication',
      'injury':         'Injury',
      'dryingOff':      'Drying Off',
      'isolation':      'Isolation',
      'shearing':       'Shearing',
      'mating':         'Mating',
      'pregnancyCheck': 'Pregnancy Check',
      'birth':          'Birth',
      'feedChange':     'Feed Change',
      'supplement':     'Supplement',
      'weightCheck':    'Weight Check',
      'milkLog':        'Milk Log',
      'sold':           'Sold',
      'deceased':       'Deceased',
      'planting':       'Planting',
      'weeding':        'Weeding',
      'fertilizer':     'Fertilizer',
      'pesticide':      'Pesticide',
      'irrigation':     'Irrigation',
      'harvest':        'Harvest',
      'cropLoss':       'Crop Loss',
      'other':          'Other',
    };
    return labels[eventType] ?? eventType;
  }

  String get emoji {
    const emojis = {
      'vaccination':    '💉',
      'deworming':      '💊',
      'vetVisit':       '🏥',
      'medication':     '💊',
      'injury':         '🩹',
      'dryingOff':      '🧴',
      'isolation':      '🚧',
      'shearing':       '✂️',
      'mating':         '🔗',
      'pregnancyCheck': '🔬',
      'birth':          '🐣',
      'feedChange':     '🌾',
      'supplement':     '🧪',
      'weightCheck':    '⚖️',
      'milkLog':        '🥛',
      'sold':           '💰',
      'deceased':       '🕊️',
      'planting':       '🌱',
      'weeding':        '🪴',
      'fertilizer':     '🧴',
      'pesticide':      '🪣',
      'irrigation':     '💧',
      'harvest':        '🌾',
      'cropLoss':       '⚠️',
      'other':          '📋',
    };
    return emojis[eventType] ?? '📋';
  }

  Map<String, dynamic> toMap() => {
        'event_id':    eventId,
        'asset_id':    assetId,
        'event_type':  eventType,
        'notes':       notes,
        'metadata':    metadata != null ? jsonEncode(metadata) : null,
        'recorded_at': recordedAt.toIso8601String(),
        'created_by':  createdBy,
        'created_at':  createdAt.toIso8601String(),
      };

  factory AssetEvent.fromMap(Map<String, dynamic> map) => AssetEvent(
        eventId:    map['event_id'] as String,
        assetId:    map['asset_id'] as String,
        eventType:  map['event_type'] as String,
        notes:      map['notes'] as String?,
        metadata:   map['metadata'] != null
            ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
            : null,
        recordedAt: DateTime.parse(map['recorded_at'] as String),
        createdBy:  map['created_by'] as String? ?? 'unknown',
        createdAt:  DateTime.parse(map['created_at'] as String),
      );

  AssetEvent copyWith({String? createdBy}) => AssetEvent(
        eventId:    eventId,
        assetId:    assetId,
        eventType:  eventType,
        notes:      notes,
        metadata:   metadata,
        recordedAt: recordedAt,
        createdBy:  createdBy ?? this.createdBy,
        createdAt:  createdAt,
      );
}

// ── MilkLog ───────────────────────────────────────────────────────────────────

class MilkLog {
  final String logId;
  final String assetId;
  final double litres;
  final MilkSession session;
  final DateTime recordedAt;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;

  const MilkLog({
    required this.logId,
    required this.assetId,
    required this.litres,
    required this.session,
    required this.recordedAt,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'log_id':      logId,
        'asset_id':    assetId,
        'litres':      litres,
        'session':     session.name,
        'recorded_at': recordedAt.toIso8601String(),
        'notes':       notes,
        'created_by':  createdBy,
        'created_at':  createdAt.toIso8601String(),
      };

  factory MilkLog.fromMap(Map<String, dynamic> map) => MilkLog(
        logId:      map['log_id'] as String,
        assetId:    map['asset_id'] as String,
        litres:     (map['litres'] as num).toDouble(),
        session:    MilkSession.values
            .byName((map['session'] as String).toLowerCase()),
        recordedAt: DateTime.parse(map['recorded_at'] as String),
        notes:      map['notes'] as String?,
        createdBy:  map['created_by'] as String? ?? 'unknown',
        createdAt:  DateTime.parse(map['created_at'] as String),
      );

  MilkLog copyWith({String? createdBy}) => MilkLog(
        logId:      logId,
        assetId:    assetId,
        litres:     litres,
        session:    session,
        recordedAt: recordedAt,
        notes:      notes,
        createdBy:  createdBy ?? this.createdBy,
        createdAt:  createdAt,
      );
}