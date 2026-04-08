// lib/data/models/asset.dart

import 'enums.dart';

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