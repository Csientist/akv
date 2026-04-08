// lib/data/models/flock_log.dart

class FlockLog {
  final String logId;
  final DateTime recordedAt;
  final String? paddockInUse;
  final int? animalsOnPasture;
  final String? supplFeedType;
  final double? qtyFed;
  final bool mineralBlockProvided;
  final bool waterIssue;
  final double feedCost;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;

  const FlockLog({
    required this.logId,
    required this.recordedAt,
    this.paddockInUse,
    this.animalsOnPasture,
    this.supplFeedType,
    this.qtyFed,
    this.mineralBlockProvided = false,
    this.waterIssue = false,
    this.feedCost = 0.0,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'log_id':                 logId,
        'recorded_at':            recordedAt.toIso8601String(),
        'paddock_in_use':         paddockInUse,
        'animals_on_pasture':     animalsOnPasture,
        'suppl_feed_type':        supplFeedType,
        'qty_fed':                qtyFed,
        'mineral_block_provided': mineralBlockProvided ? 1 : 0,
        'water_issue':            waterIssue ? 1 : 0,
        'feed_cost':              feedCost,
        'notes':                  notes,
        'created_by':             createdBy,
        'created_at':             createdAt.toIso8601String(),
      };

  factory FlockLog.fromMap(Map<String, dynamic> map) => FlockLog(
        logId:                map['log_id'] as String,
        recordedAt:           DateTime.parse(map['recorded_at'] as String),
        paddockInUse:         map['paddock_in_use'] as String?,
        animalsOnPasture:     map['animals_on_pasture'] as int?,
        supplFeedType:        map['suppl_feed_type'] as String?,
        qtyFed:               (map['qty_fed'] as num?)?.toDouble(),
        mineralBlockProvided: (map['mineral_block_provided'] as int?) == 1,
        waterIssue:           (map['water_issue'] as int?) == 1,
        feedCost:             (map['feed_cost'] as num?)?.toDouble() ?? 0.0,
        notes:                map['notes'] as String?,
        createdBy:            map['created_by'] as String? ?? 'unknown',
        createdAt:            DateTime.parse(map['created_at'] as String),
      );

  FlockLog copyWith({String? createdBy}) => FlockLog(
        logId:                logId,
        recordedAt:           recordedAt,
        paddockInUse:         paddockInUse,
        animalsOnPasture:     animalsOnPasture,
        supplFeedType:        supplFeedType,
        qtyFed:               qtyFed,
        mineralBlockProvided: mineralBlockProvided,
        waterIssue:           waterIssue,
        feedCost:             feedCost,
        notes:                notes,
        createdBy:            createdBy ?? this.createdBy,
        createdAt:            createdAt,
      );
}