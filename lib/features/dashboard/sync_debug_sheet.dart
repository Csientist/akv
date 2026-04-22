import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import '../../core/appwrite_client.dart';
import '../../core/local_db.dart';
import '../../services/sync_service.dart';
import '../../services/session_manager.dart';

class SyncDebugSheet extends StatefulWidget {
  const SyncDebugSheet({super.key});

  @override
  State<SyncDebugSheet> createState() => _SyncDebugSheetState();
}

class _SyncDebugSheetState extends State<SyncDebugSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(children: [
            const Text('Sync Diagnostics',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.restore, color: Colors.orange),
              tooltip: 'Revive failed items',
              onPressed: () async {
                await LocalDb.instance.resetFailedQueue();
                setState(() {});
              },
            ),
            IconButton(
              icon: const Icon(Icons.sync, color: Color(0xFF2D6A4F)),
              tooltip: 'Force full sync',
              onPressed: () {
                SyncService().fullSync();
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) setState(() {});
                });
              },
            ),
          ]),
        ),
        TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF2D6A4F),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF2D6A4F),
          tabs: const [
            Tab(text: 'Sync Queue'),
            Tab(text: 'Conflicts'),
            Tab(text: 'DB Inspector'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _QueueTab(onChanged: () => setState(() {})),
              const _ConflictsTab(),
              const _DbInspectorTab(),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Queue Tab ─────────────────────────────────────────────────────────────────

class _QueueTab extends StatelessWidget {
  final VoidCallback onChanged;
  const _QueueTab({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: LocalDb.instance.getPendingQueue(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final queue = snap.data ?? [];
        if (queue.isEmpty) {
          return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_done_outlined,
                  size: 48, color: Color(0xFF52B788)),
              SizedBox(height: 12),
              Text('Queue is empty — all synced!',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D6A4F))),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: queue.length,
          itemBuilder: (context, i) {
            final item       = queue[i];
            final retries    = item['retry_count'] as int? ?? 0;
            final isPoisoned = retries >= 5;
            return Card(
              color: isPoisoned ? Colors.red.shade50 : Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  isPoisoned
                      ? Icons.error_outline
                      : Icons.cloud_upload_outlined,
                  color: isPoisoned ? Colors.red : const Color(0xFF2D6A4F),
                ),
                title: Text(item['table_name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${item['operation']}  ·  ${item['record_id']}',
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  'Retries: $retries',
                  style: TextStyle(
                    color: isPoisoned ? Colors.red : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Conflicts Tab (REFACORED FOR 1.8.0) ───────────────────────────────────────

class _ConflictsTab extends StatefulWidget {
  const _ConflictsTab();

  @override
  State<_ConflictsTab> createState() => _ConflictsTabState();
}

class _ConflictsTabState extends State<_ConflictsTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchConflicts();
  }

  Future<List<Map<String, dynamic>>> _fetchConflicts() async {
    try {
      // MIGRATION: listRows replaces listDocuments
      final result = await AppwriteClient.instance.tablesDB.listRows(
        databaseId:   AppwriteClient.kDatabaseId,
        tableId:      AppwriteClient.colSyncConflicts,
        queries: [
          Query.orderDesc('conflict_at'),
          Query.limit(50),
        ],
      );
      
      // result.rows replaces result.documents
      return result.rows
          .map((row) => {...row.data, '\$id': row.$id})
          .toList();
    } on AppwriteException catch (e) {
      if (e.code == 404) return [];
      rethrow;
    }
  }

  Future<void> _deleteOne(String rowId) async {
    try {
      // MIGRATION: deleteRow replaces deleteDocument
      await AppwriteClient.instance.tablesDB.deleteRow(
        databaseId:   AppwriteClient.kDatabaseId,
        tableId:      AppwriteClient.colSyncConflicts,
        rowId:        rowId,
      );
    } catch (_) {}
    setState(() => _future = _fetchConflicts());
  }

  Future<void> _clearAll(List<Map<String, dynamic>> rows) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all conflicts?'),
        content: Text(
            'Permanently delete ${rows.length} '
            'conflict record${rows.length > 1 ? 's' : ''} from Appwrite.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    
    for (final row in rows) {
      final id = (row['\$id'] ?? row['conflict_id']) as String;
      try {
        await AppwriteClient.instance.tablesDB.deleteRow(
          databaseId:   AppwriteClient.kDatabaseId,
          tableId:      AppwriteClient.colSyncConflicts,
          rowId:        id,
        );
      } catch (_) {}
    }
    setState(() => _future = _fetchConflicts());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text('Could not load conflicts\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
          );
        }
        final docs = snap.data ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_outline,
                  size: 48, color: Color(0xFF52B788)),
              SizedBox(height: 12),
              Text('No conflicts recorded',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D6A4F))),
              SizedBox(height: 4),
              Text('All down-syncs resolved cleanly.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          );
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Text('${docs.length} conflict${docs.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _clearAll(docs),
                icon: const Icon(Icons.delete_sweep_outlined,
                    size: 16, color: Colors.red),
                label: const Text('Clear All',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final doc   = docs[i];
                final docId = (doc['\$id'] ?? doc['conflict_id']) as String;
                final table = doc['table_name'] as String? ?? '';
                final recId = doc['record_id']  as String? ?? '';
                final at    = doc['conflict_at'] as String? ?? '';
                return Dismissible(
                  key: ValueKey(docId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  onDismissed: (_) => _deleteOne(docId),
                  child: Card(
                    color: Colors.orange.shade50,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange),
                      title: Text(table,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      subtitle: Text(recId,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Text(_relDate(at),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      onTap: () => _showDetail(context, doc),
                    ),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConflictDetailSheet(doc: doc),
    );
  }

  String _relDate(String iso) {
    try {
      final dt   = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24) return '${diff.inHours}h ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Conflict Detail Sheet ─────────────────────────────────────────────────────

class _ConflictDetailSheet extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _ConflictDetailSheet({required this.doc});

  @override
  Widget build(BuildContext context) {
    final table    = doc['table_name']  as String? ?? '';
    final recordId = doc['record_id']   as String? ?? '';
    final at       = doc['conflict_at'] as String? ?? '';

    Map<String, dynamic> diff = {};
    try {
      final raw = doc['diff_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        diff = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$table / $recordId',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _InfoRow('Table',      table),
              _InfoRow('Record ID',  recordId),
              _InfoRow('Detected',   at),
              _InfoRow('Resolution', 'Appwrite version kept'),
              const SizedBox(height: 16),
              const Text('CHANGED FIELDS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D6A4F),
                      letterSpacing: 1.4)),
              const SizedBox(height: 8),
              if (diff.isEmpty)
                const Text('No diff available',
                    style: TextStyle(color: Colors.grey))
              else
                ...diff.entries.map((e) {
                  Map<String, dynamic> fieldDiff = {};
                  try {
                    fieldDiff = jsonDecode(e.value as String)
                        as Map<String, dynamic>;
                  } catch (_) {}
                  final local  = fieldDiff['local'];
                  final remote = fieldDiff['remote'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                fontFamily: 'monospace')),
                        const SizedBox(height: 6),
                        Row(children: [
                          const _DiffBadge('LOCAL', Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('$local',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          const _DiffBadge('CLOUD', Color(0xFF2D6A4F)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('$remote',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF1B4332)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF111827))),
          ),
        ]),
      );
}

class _DiffBadge extends StatelessWidget {
  final String text;
  final Color  color;
  const _DiffBadge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.5)),
      );
}

// ── DB Inspector Tab ──────────────────────────────────────────────────────────

class _DbInspectorTab extends StatefulWidget {
  const _DbInspectorTab();
  @override
  State<_DbInspectorTab> createState() => _DbInspectorTabState();
}

class _DbInspectorTabState extends State<_DbInspectorTab> {
  late Future<_DbSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _snapshot();
  }

  Future<_DbSnapshot> _snapshot() async {
    final db  = await LocalDb.instance.database;
    final uid = SessionManager.instance.currentUserId;

    Future<int> count(String table, {bool myRows = false}) async {
      final where = myRows ? 'WHERE created_by = ?' : '';
      final args  = myRows ? [uid] : [];
      final r = await db.rawQuery(
          'SELECT COUNT(*) as c FROM $table $where', args);
      return (r.first['c'] as int?) ?? 0;
    }

    final tables = [
      'financials', 'assets', 'inventory', 'ledger_entries',
      'asset_events', 'milk_logs', 'partial_payments',
    ];

    final counts = <String, _TableCount>{};
    for (final t in tables) {
      counts[t] = _TableCount(
        total: await count(t),
        mine:  await count(t, myRows: true),
      );
    }

    final rows = await db.query(
      'financials',
      orderBy: 'created_at DESC',
      limit: 8,
    );

    return _DbSnapshot(
      userId:  uid,
      counts:  counts,
      recentFinancials: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DbSnapshot>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}',
              style: const TextStyle(color: Colors.red)));
        }
        final s = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _InspectorSection(
              label: 'SESSION',
              child: _MonoRow('User ID', s.userId),
            ),
            const SizedBox(height: 12),
            _InspectorSection(
              label: 'TABLE COUNTS  (total / mine)',
              child: Column(
                children: s.counts.entries.map((e) {
                  final match = e.value.mine == e.value.total;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text(e.key,
                          style: const TextStyle(
                              fontSize: 12, fontFamily: 'monospace'))),
                      Text(
                        '${e.value.total} total / ${e.value.mine} mine',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: e.value.total == 0
                              ? Colors.grey
                              : match
                                  ? const Color(0xFF2D6A4F)
                                  : Colors.orange.shade700,
                        ),
                      ),
                    ]),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            _InspectorSection(
              label: 'RECENT FINANCIALS (ALL USERS)',
              child: s.recentFinancials.isEmpty
                  ? const Text('No rows in financials table.',
                      style: TextStyle(color: Colors.grey, fontSize: 12))
                  : Column(
                      children: s.recentFinancials.map((row) {
                        final mine = row['created_by'] == s.userId;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFFEAF7EF)
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: mine
                                  ? const Color(0xFFB7E4C7)
                                  : Colors.orange.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(
                                    '${row['transaction_type']?.toString().toUpperCase()} — '
                                    '${row['customer_supplier_name']}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  'KES ${row['amount']}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800),
                                ),
                              ]),
                              const SizedBox(height: 2),
                              Text(
                                'by: ${row['created_by']}',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: mine
                                        ? const Color(0xFF2D6A4F)
                                        : Colors.orange.shade800,
                                    fontFamily: 'monospace'),
                              ),
                              Text(
                                '${row['created_at']}  ·  '
                                '${row['payment_status']}  ·  '
                                '${row['payment_method']}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _future = _snapshot()),
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Refresh', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InspectorSection extends StatelessWidget {
  final String label;
  final Widget child;
  const _InspectorSection({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD8E8E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D6A4F),
                  letterSpacing: 1.3)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

class _MonoRow extends StatelessWidget {
  final String label;
  final String value;
  const _MonoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF111827))),
          ),
        ],
      );
}

class _DbSnapshot {
  final String userId;
  final Map<String, _TableCount> counts;
  final List<Map<String, dynamic>> recentFinancials;
  const _DbSnapshot({
    required this.userId,
    required this.counts,
    required this.recentFinancials,
  });
}

class _TableCount {
  final int total;
  final int mine;
  const _TableCount({required this.total, required this.mine});
}