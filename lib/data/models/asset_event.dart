// lib/data/models/asset_event.dart

import 'dart:convert';

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
      'deworming':      'Deworming',
      'vetVisit':       'Vet Visit',
      'medication':     'Medication',
      'hoofTrim':       'Hoof Trim',
      'dipping':        'Dipping',
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
      'deworming':      '💊',
      'vetVisit':       '🏥',
      'medication':     '💊',
      'hoofTrim':       '🪚',
      'dipping':        '🛁',
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