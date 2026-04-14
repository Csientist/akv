// lib/data/models/ledger_entry.dart

import 'dart:convert';
import 'enums.dart';

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