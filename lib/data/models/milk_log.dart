// lib/data/models/milk_log.dart

import 'enums.dart';

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