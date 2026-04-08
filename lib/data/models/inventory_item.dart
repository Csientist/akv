// lib/data/models/inventory_item.dart

import 'enums.dart';

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
    String?            itemName,
    InventoryCategory? category,
    double?            quantity,
    InventoryUnit?     unit,
    double?            reorderLevel,
    String?            notes,
    String?            createdBy,
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