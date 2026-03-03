import 'dart:convert';

enum LedgerType { SALE, PURCHASE, HERD_UPDATE, INVENTORY_ADJUST }
enum LedgerStatus { pending, completed, failed }

class LedgerEntry {
  final String eventId;
  final LedgerType type;
  final String sourceId;
  final double amount;
  final LedgerStatus status;
  final Map<String, dynamic>? metadata; // M-PESA receipt, KRA signature
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
      // Fallback to 0.0 if amount is missing
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      status: LedgerStatus.values.byName(map['status'] as String),
      metadata: map['metadata'] != null
          ? (map['metadata'] is String 
              ? jsonDecode(map['metadata'] as String) 
              : map['metadata']) as Map<String, dynamic>
          : null,
      // Parse and force UTC for global consistency
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
}

// ── Asset Model ───────────────────────────────────────────────────────────────

enum AssetCategory { LIVESTOCK, CROP }
enum AssetStatus { ACTIVE, SOLD, DECEASED }

class Asset {
  final String assetId;
  final AssetCategory category;
  final String breedType;
  final AssetStatus status;
  final String? lastEventId;
  final DateTime createdAt;

  const Asset({
    required this.assetId,
    required this.category,
    required this.breedType,
    this.status = AssetStatus.ACTIVE,
    this.lastEventId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'asset_id': assetId,
        'category': category.name,
        'breed_type': breedType,
        'status': status.name,
        'last_event_id': lastEventId,
        'created_at': createdAt.toIso8601String(),
      };

  factory Asset.fromMap(Map<String, dynamic> map) => Asset(
        assetId: map['asset_id'] as String,
        category: AssetCategory.values.byName(map['category'] as String),
        breedType: map['breed_type'] as String,
        status: AssetStatus.values.byName(map['status'] as String),
        lastEventId: map['last_event_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

// ── Inventory Model ───────────────────────────────────────────────────────────

enum InventoryUnit { KG, LITRES, BAGS }

class InventoryItem {
  final String itemId;
  final String itemName;
  final double quantity;
  final InventoryUnit unit;
  final double reorderLevel;
  final DateTime createdAt;

  bool get isLowStock => quantity <= reorderLevel;

  const InventoryItem({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.reorderLevel,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'item_id': itemId,
        'item_name': itemName,
        'quantity': quantity,
        'unit': unit.name,
        'reorder_level': reorderLevel,
        'created_at': createdAt.toIso8601String(),
      };

  factory InventoryItem.fromMap(Map<String, dynamic> map) => InventoryItem(
        itemId: map['item_id'] as String,
        itemName: map['item_name'] as String,
        quantity: (map['quantity'] as num).toDouble(),
        unit: InventoryUnit.values.byName(map['unit'] as String),
        reorderLevel: (map['reorder_level'] as num).toDouble(),
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

// ── Financial Model ───────────────────────────────────────────────────────────

enum PaymentMethod { MPESA, CASH, BANK }

class Financial {
  final String transactionId;
  final String customerSupplierName;
  final PaymentMethod paymentMethod;
  final double amount;
  final bool isKraCertified;
  final String? kraReference;
  final String? eventId;
  final DateTime createdAt;

  const Financial({
    required this.transactionId,
    required this.customerSupplierName,
    required this.paymentMethod,
    required this.amount,
    this.isKraCertified = false,
    this.kraReference,
    this.eventId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'transaction_id': transactionId,
        'customer_supplier_name': customerSupplierName,
        'payment_method': paymentMethod.name,
        'amount': amount,
        'is_kra_certified': isKraCertified ? 1 : 0,
        'kra_reference': kraReference,
        'event_id': eventId,
        'created_at': createdAt.toIso8601String(),
      };

  factory Financial.fromMap(Map<String, dynamic> map) => Financial(
      transactionId: map['transaction_id'] as String,
      customerSupplierName: map['customer_supplier_name'] as String,
      paymentMethod: PaymentMethod.values.byName(map['payment_method'] as String),
      amount: (map['amount'] as num).toDouble(),
      // Handle both SQLite (int) and Appwrite (bool)
      isKraCertified: map['is_kra_certified'] is int 
          ? (map['is_kra_certified'] as int) == 1 
          : (map['is_kra_certified'] as bool? ?? false),
      kraReference: map['kra_reference'] as String?,
      eventId: map['event_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
}