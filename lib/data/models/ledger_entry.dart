import 'dart:convert';

enum LedgerType { SALE, PURCHASE, HERD_UPDATE, INVENTORY_ADJUST }
enum LedgerStatus { pending, completed, failed }

class LedgerEntry {
  final String eventId;
  final LedgerType type;
  final String sourceId;
  final double amount;
  final LedgerStatus status;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const LedgerEntry({
    required this.eventId,
    required this.type,
    required this.sourceId,
    this.amount = 0.0,
    this.status = LedgerStatus.pending,
    this.metadata,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'event_id': eventId,
        'type': type.name,
        'source_id': sourceId,
        'amount': amount,
        'status': status.name,
        'metadata': metadata != null ? jsonEncode(metadata) : null,
        'created_at': createdAt.toIso8601String(),
      };

  factory LedgerEntry.fromMap(Map<String, dynamic> map) => LedgerEntry(
        eventId: map['event_id'] as String,
        type: LedgerType.values.byName(map['type'] as String),
        sourceId: map['source_id'] as String,
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        status: LedgerStatus.values.byName(map['status'] as String),
        metadata: map['metadata'] != null
            ? (map['metadata'] is String
                ? jsonDecode(map['metadata'] as String)
                : map['metadata']) as Map<String, dynamic>
            : null,
        createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      );
}

// ── Asset Model (upgraded with tag, weight, age, health notes) ─────────────

enum AssetCategory { LIVESTOCK, CROP }
enum AssetStatus { ACTIVE, SOLD, DECEASED }

class Asset {
  final String assetId;
  final String tagName;       // e.g. "Daisy", "Bull-003", "Pen-A2"
  final AssetCategory category;
  final String breedType;
  final AssetStatus status;
  final double? weightKg;
  final DateTime? dateOfBirth;
  final String? healthNotes;
  final String? lastEventId;
  final DateTime createdAt;

  const Asset({
    required this.assetId,
    required this.tagName,
    required this.category,
    required this.breedType,
    this.status = AssetStatus.ACTIVE,
    this.weightKg,
    this.dateOfBirth,
    this.healthNotes,
    this.lastEventId,
    required this.createdAt,
  });

  /// Dynamically computed from dateOfBirth to today.
  String get displayAge {
    if (dateOfBirth == null) return 'Unknown age';
    final now = DateTime.now();
    int months = (now.year - dateOfBirth!.year) * 12 + (now.month - dateOfBirth!.month);
    if (now.day < dateOfBirth!.day) months--;
    if (months < 0) months = 0;
    if (months < 12) return '${months}mo';
    final years = months ~/ 12;
    final rem = months % 12;
    return rem > 0 ? '${years}yr ${rem}mo' : '${years}yr';
  }

  /// Total months alive, for sorting/filtering.
  int get ageInMonths {
    if (dateOfBirth == null) return 0;
    final now = DateTime.now();
    int months = (now.year - dateOfBirth!.year) * 12 + (now.month - dateOfBirth!.month);
    if (now.day < dateOfBirth!.day) months--;
    return months < 0 ? 0 : months;
  }

  Map<String, dynamic> toMap() => {
        'asset_id': assetId,
        'tag_name': tagName,
        'category': category.name,
        'breed_type': breedType,
        'status': status.name,
        'weight_kg': weightKg,
        'date_of_birth': dateOfBirth?.toIso8601String().substring(0, 10),
        'health_notes': healthNotes,
        'last_event_id': lastEventId,
        'created_at': createdAt.toIso8601String(),
      };

  factory Asset.fromMap(Map<String, dynamic> map) => Asset(
        assetId: map['asset_id'] as String,
        tagName: map['tag_name'] as String? ?? '',
        category: AssetCategory.values.byName(map['category'] as String),
        breedType: map['breed_type'] as String,
        status: AssetStatus.values.byName(map['status'] as String),
        weightKg: (map['weight_kg'] as num?)?.toDouble(),
        dateOfBirth: map['date_of_birth'] != null
            ? DateTime.tryParse(map['date_of_birth'] as String)
            : null,
        healthNotes: map['health_notes'] as String?,
        lastEventId: map['last_event_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Asset copyWith({
    String? tagName,
    AssetStatus? status,
    double? weightKg,
    DateTime? dateOfBirth,
    String? healthNotes,
    String? lastEventId,
  }) =>
      Asset(
        assetId: assetId,
        tagName: tagName ?? this.tagName,
        category: category,
        breedType: breedType,
        status: status ?? this.status,
        weightKg: weightKg ?? this.weightKg,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        healthNotes: healthNotes ?? this.healthNotes,
        lastEventId: lastEventId ?? this.lastEventId,
        createdAt: createdAt,
      );
}

// ── Inventory Model (upgraded with category and notes) ──────────────────────

enum InventoryUnit { KG, LITRES, BAGS, PIECES, VIALS }
enum InventoryCategory { FEED, MEDICINE, EQUIPMENT, SEED, OTHER }

class InventoryItem {
  final String itemId;
  final String itemName;
  final InventoryCategory category;
  final double quantity;
  final InventoryUnit unit;
  final double reorderLevel;
  final String? notes;
  final DateTime createdAt;

  bool get isLowStock => quantity <= reorderLevel;

  double get stockPercent =>
      reorderLevel == 0 ? 1.0 : (quantity / (reorderLevel * 3)).clamp(0.0, 1.0);

  const InventoryItem({
    required this.itemId,
    required this.itemName,
    this.category = InventoryCategory.FEED,
    required this.quantity,
    required this.unit,
    required this.reorderLevel,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'item_id': itemId,
        'item_name': itemName,
        'category': category.name,
        'quantity': quantity,
        'unit': unit.name,
        'reorder_level': reorderLevel,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };

  factory InventoryItem.fromMap(Map<String, dynamic> map) => InventoryItem(
        itemId: map['item_id'] as String,
        itemName: map['item_name'] as String,
        category: InventoryCategory.values.byName(
            (map['category'] as String?) ?? 'FEED'),
        quantity: (map['quantity'] as num).toDouble(),
        unit: InventoryUnit.values.byName(map['unit'] as String),
        reorderLevel: (map['reorder_level'] as num).toDouble(),
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  InventoryItem copyWith({double? quantity}) => InventoryItem(
        itemId: itemId,
        itemName: itemName,
        category: category,
        quantity: quantity ?? this.quantity,
        unit: unit,
        reorderLevel: reorderLevel,
        notes: notes,
        createdAt: createdAt,
      );
}

// ── Financial Model (upgraded with transaction_type and description) ─────────

enum PaymentMethod { MPESA, CASH, BANK }
enum TransactionType { SALE, PURCHASE }

class Financial {
  final String transactionId;
  final TransactionType transactionType;
  final String customerSupplierName;
  final PaymentMethod paymentMethod;
  final double amount;
  final String? description;
  final bool isKraCertified;
  final String? kraReference;
  final String? eventId;
  final DateTime createdAt;

  const Financial({
    required this.transactionId,
    this.transactionType = TransactionType.SALE,
    required this.customerSupplierName,
    required this.paymentMethod,
    required this.amount,
    this.description,
    this.isKraCertified = false,
    this.kraReference,
    this.eventId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'transaction_id': transactionId,
        'transaction_type': transactionType.name,
        'customer_supplier_name': customerSupplierName,
        'payment_method': paymentMethod.name,
        'amount': amount,
        'description': description,
        'is_kra_certified': isKraCertified ? 1 : 0,
        'kra_reference': kraReference,
        'event_id': eventId,
        'created_at': createdAt.toIso8601String(),
      };

  factory Financial.fromMap(Map<String, dynamic> map) => Financial(
        transactionId: map['transaction_id'] as String,
        transactionType: TransactionType.values.byName(
            (map['transaction_type'] as String?) ?? 'SALE'),
        customerSupplierName: map['customer_supplier_name'] as String,
        paymentMethod: PaymentMethod.values.byName(map['payment_method'] as String),
        amount: (map['amount'] as num).toDouble(),
        description: map['description'] as String?,
        isKraCertified: map['is_kra_certified'] is int
            ? (map['is_kra_certified'] as int) == 1
            : (map['is_kra_certified'] as bool? ?? false),
        kraReference: map['kra_reference'] as String?,
        eventId: map['event_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      );
}

// ── Dashboard Summary Model ───────────────────────────────────────────────────

class DashboardSummary {
  final double totalSalesAllTime;
  final double totalPurchasesAllTime;
  final double totalSalesThisMonth;
  final int livestockCount;
  final int cropCount;
  final int lowStockCount;
  final int pendingSyncCount;
  final List<Financial> recentTransactions;

  const DashboardSummary({
    required this.totalSalesAllTime,
    required this.totalPurchasesAllTime,
    required this.totalSalesThisMonth,
    required this.livestockCount,
    required this.cropCount,
    required this.lowStockCount,
    required this.pendingSyncCount,
    required this.recentTransactions,
  });

  double get netPosition => totalSalesAllTime - totalPurchasesAllTime;
}

// ── Asset Event Types ─────────────────────────────────────────────────────────

enum LivestockEventType {
  // Health
  vaccination, deworming, vetVisit, medication, injury,
  // Breeding
  mating, pregnancyCheck, birth,
  // Feeding
  feedChange, supplement,
  // Production
  weightCheck, milkLog,
  // Status
  sold, deceased,
}

enum CropEventType {
  planting, weeding, fertilizer, pesticide, irrigation,
  harvest, cropLoss, other,
}

// ── Asset Event Model ─────────────────────────────────────────────────────────

class AssetEvent {
  final String eventId;
  final String assetId;
  final String eventType;   // raw string — covers both livestock + crop enums
  final String? notes;
  final Map<String, dynamic>? metadata;
  final DateTime recordedAt;
  final DateTime createdAt;

  const AssetEvent({
    required this.eventId,
    required this.assetId,
    required this.eventType,
    this.notes,
    this.metadata,
    required this.recordedAt,
    required this.createdAt,
  });

  // Human-readable label
  String get displayLabel {
    // Livestock
    switch (eventType) {
      case 'vaccination':    return 'Vaccination';
      case 'deworming':      return 'Deworming';
      case 'vetVisit':       return 'Vet Visit';
      case 'medication':     return 'Medication';
      case 'injury':         return 'Injury';
      case 'mating':         return 'Mating';
      case 'pregnancyCheck': return 'Pregnancy Check';
      case 'birth':          return 'Birth';
      case 'feedChange':     return 'Feed Change';
      case 'supplement':     return 'Supplement';
      case 'weightCheck':    return 'Weight Check';
      case 'milkLog':        return 'Milk Log';
      case 'sold':           return 'Sold';
      case 'deceased':       return 'Deceased';
      // Crop
      case 'planting':       return 'Planting';
      case 'weeding':        return 'Weeding';
      case 'fertilizer':     return 'Fertilizer';
      case 'pesticide':      return 'Pesticide';
      case 'irrigation':     return 'Irrigation';
      case 'harvest':        return 'Harvest';
      case 'cropLoss':       return 'Crop Loss';
      default:               return eventType;
    }
  }

  String get emoji {
    switch (eventType) {
      case 'vaccination':    return '💉';
      case 'deworming':      return '💊';
      case 'vetVisit':       return '🏥';
      case 'medication':     return '💊';
      case 'injury':         return '🩹';
      case 'mating':         return '🔗';
      case 'pregnancyCheck': return '🔬';
      case 'birth':          return '🐣';
      case 'feedChange':     return '🌾';
      case 'supplement':     return '🧪';
      case 'weightCheck':    return '⚖️';
      case 'milkLog':        return '🥛';
      case 'sold':           return '💰';
      case 'deceased':       return '🕊️';
      case 'planting':       return '🌱';
      case 'weeding':        return '🪴';
      case 'fertilizer':     return '🧴';
      case 'pesticide':      return '🪣';
      case 'irrigation':     return '💧';
      case 'harvest':        return '🌾';
      case 'cropLoss':       return '⚠️';
      default:               return '📋';
    }
  }

  Map<String, dynamic> toMap() => {
        'event_id': eventId,
        'asset_id': assetId,
        'event_type': eventType,
        'notes': notes,
        'metadata': metadata != null ? jsonEncode(metadata) : null,
        'recorded_at': recordedAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  factory AssetEvent.fromMap(Map<String, dynamic> map) => AssetEvent(
        eventId: map['event_id'] as String,
        assetId: map['asset_id'] as String,
        eventType: map['event_type'] as String,
        notes: map['notes'] as String?,
        metadata: map['metadata'] != null
            ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
            : null,
        recordedAt: DateTime.parse(map['recorded_at'] as String),
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

// ── Milk Log Model ────────────────────────────────────────────────────────────

enum MilkSession { AM, PM, FULL }

class MilkLog {
  final String logId;
  final String assetId;
  final double litres;
  final MilkSession session;
  final DateTime recordedAt;
  final String? notes;

  const MilkLog({
    required this.logId,
    required this.assetId,
    required this.litres,
    required this.session,
    required this.recordedAt,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
        'log_id': logId,
        'asset_id': assetId,
        'litres': litres,
        'session': session.name,
        'recorded_at': recordedAt.toIso8601String(),
        'notes': notes,
      };

  factory MilkLog.fromMap(Map<String, dynamic> map) => MilkLog(
        logId: map['log_id'] as String,
        assetId: map['asset_id'] as String,
        litres: (map['litres'] as num).toDouble(),
        session: MilkSession.values.byName(map['session'] as String),
        recordedAt: DateTime.parse(map['recorded_at'] as String),
        notes: map['notes'] as String?,
      );
}