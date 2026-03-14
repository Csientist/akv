import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/ledger_entry.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../services/app_refresh_service.dart';
import '../../services/sync_service.dart';
import 'sync_debug_sheet.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _repo = LedgerRepository();

  // Keep the last successfully loaded summary so we can show stale data
  // while a new load is in progress — avoids the full-screen spinner on
  // every refresh tick.
  DashboardSummary? _data;
  bool _loading = false;
  Object?  _error;

  StreamSubscription<void>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshSub = AppRefreshService.instance.ticks.listen((_) {
        if (mounted) _load();
      });
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final summary = await _repo.getDashboardSummary();
      if (mounted) setState(() { _data = summary; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  // Trigger a full sync then reload — used by the manual refresh button
  // and pull-to-refresh so the user always gets fresh cloud data on demand.
  Future<void> _syncAndLoad() async {
    await SyncService().fullSync();
    await _load();
  }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Farm Manager',
            style: TextStyle(
                fontFamily: 'Lora',
                fontWeight: FontWeight.bold,
                color: scheme.primary)),
        actions: [
          // Show a spinner in the app bar while syncing/loading,
          // otherwise show the manual refresh button.
          if (_loading && _data != null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF2D6A4F)),
              ),
            )
          else
            IconButton(
              onPressed: _syncAndLoad,
              icon: const Icon(Icons.sync_rounded),
              color: const Color(0xFF2D6A4F),
              tooltip: 'Sync & Refresh',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // First load — no data yet
    if (_data == null && _loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2D6A4F)));
    }

    // First load failed
    if (_data == null && _error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('Could not load data',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }

    final s = _data!;

    return RefreshIndicator(
      color: const Color(0xFF2D6A4F),
      onRefresh: _syncAndLoad,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // ── Sync Status ────────────────────────────────────────────────
          SyncBanner(pendingCount: s.pendingSyncCount),
          const SizedBox(height: 20),

          // ── Net Position Hero Card ──────────────────────────────────────
          _NetPositionCard(summary: s),
          const SizedBox(height: 20),

          // ── Quick Stats Grid ────────────────────────────────────────────
          const _SectionLabel('Quick Stats'),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _StatCard(
                icon: Icons.trending_up,
                label: 'This Month',
                value: _fmt(s.totalSalesThisMonth),
                color: const Color(0xFF2D6A4F),
              ),
              _StatCard(
                icon: Icons.hourglass_top_outlined,
                label: 'Outstanding',
                value: s.totalOutstanding == 0
                    ? 'All paid ✓'
                    : _fmt(s.totalOutstanding),
                color: s.totalOutstanding > 0
                    ? Colors.orange.shade700
                    : const Color(0xFF2D6A4F),
                alert: s.totalOutstanding > 0,
              ),
              _StatCard(
                icon: Icons.pets,
                label: 'Livestock',
                value: '${s.livestockCount} head',
                color: const Color(0xFF2D6A4F),
              ),
              _StatCard(
                icon: Icons.inventory_2_outlined,
                label: 'Low Stock',
                value: s.lowStockCount == 0
                    ? 'All good ✓'
                    : '${s.lowStockCount} item${s.lowStockCount > 1 ? 's' : ''}',
                color: s.lowStockCount > 0
                    ? Colors.orange.shade700
                    : const Color(0xFF2D6A4F),
                alert: s.lowStockCount > 0,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Recent Activity ─────────────────────────────────────────────
          Row(children: [
            const _SectionLabel('Recent Activity'),
            const Spacer(),
            if (s.recentTransactions.isNotEmpty)
              Text(
                '${s.recentTransactions.length} transactions',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500),
              ),
          ]),
          const SizedBox(height: 12),
          if (s.recentTransactions.isEmpty)
            _EmptyActivity()
          else
            ...s.recentTransactions.map((t) => _ActivityTile(txn: t)),

          // ── Totals footer ───────────────────────────────────────────────
          if (s.recentTransactions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD8E8E0)),
              ),
              child: Row(children: [
                _FooterStat('All-time Sales',
                    _fmt(s.totalSalesAllTime), const Color(0xFF2D6A4F)),
                Container(width: 1, height: 28,
                    color: const Color(0xFFD8E8E0),
                    margin: const EdgeInsets.symmetric(horizontal: 16)),
                _FooterStat('All-time Purchases',
                    _fmt(s.totalPurchasesAllTime), const Color(0xFF9B2226)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(double amount) {
    if (amount >= 1000000) return 'KES ${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000)    return 'KES ${(amount / 1000).toStringAsFixed(1)}k';
    return 'KES ${amount.toStringAsFixed(0)}';
  }
}

// ── Sync Banner ───────────────────────────────────────────────────────────────
class SyncBanner extends StatelessWidget {
  final int pendingCount;
  
  const SyncBanner({super.key, required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    final isOnline = pendingCount == 0;
    
    // UI Theme based on sync state
    final bg     = isOnline ? const Color(0xFFD8F3DC) : Colors.orange.shade50;
    final border = isOnline ? const Color(0xFFB7E4C7) : Colors.orange.shade200;
    final dot    = isOnline ? const Color(0xFF2D6A4F) : Colors.orange;
    final label  = isOnline 
        ? 'All data synced' 
        : '$pendingCount record${pendingCount > 1 ? 's' : ''} pending sync';

    return Material(
      color: bg,
      //borderRadius: BorderRadius.circular(12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      // Clip to ensure the InkWell ripple stays inside the rounded borders
      clipBehavior: Clip.antiAlias, 
      child: InkWell(
        // THE SECRET TRIGGER
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true, 
            backgroundColor: Colors.transparent,
            builder: (context) => const SyncDebugSheet(),
          );
        },
        // Helpful toast for normal taps
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOnline 
                    ? 'Your data is safely backed up to the cloud.'
                    : 'Syncing in background... Long-press for details.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _PulseDot(color: dot, animate: !isOnline),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: isOnline ? const Color(0xFF2D6A4F) : Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Icon(
                isOnline ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
                color: isOnline ? const Color(0xFF2D6A4F) : Colors.orange.shade700,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pulse Animation Helper ───────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool animate;
  
  const _PulseDot({required this.color, required this.animate});
  
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { 
    _ctrl.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return Container(
        width: 8, 
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8, 
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
// ── Net Position Hero Card ────────────────────────────────────────────────────

class _NetPositionCard extends StatelessWidget {
  final DashboardSummary summary;
  const _NetPositionCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final net = summary.netPosition;
    final isPositive = net >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4332),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Net Position',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w500)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isPositive ? const Color(0xFF52B788) : Colors.red.shade400,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Text(isPositive ? 'Profit' : 'Loss',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          _fmt(net.abs()),
          style: const TextStyle(
              color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1),
        ),
        const SizedBox(height: 16),
        Row(children: [
          _MiniStat('Sales', _fmt(summary.totalSalesAllTime), Icons.trending_up),
          Container(width: 1, height: 30, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 16)),
          _MiniStat('Purchases', _fmt(summary.totalPurchasesAllTime), Icons.trending_down),
          Container(width: 1, height: 30, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 16)),
          _MiniStat('Herd', '${summary.livestockCount + summary.cropCount} assets', Icons.pets),
        ]),
      ]),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return 'KES ${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return 'KES ${(v / 1000).toStringAsFixed(1)}k';
    return 'KES ${v.toStringAsFixed(0)}';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MiniStat(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 11, color: Colors.white54),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool alert;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alert ? Colors.orange.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: alert ? Colors.orange.shade200 : const Color(0xFFD8E8E0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        Text(value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ── Recent Activity ───────────────────────────────────────────────────────────

class _ActivityTile extends StatelessWidget {
  final Financial txn;
  const _ActivityTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isSale = txn.transactionType == TransactionType.sale;
    final color = isSale ? const Color(0xFF2D6A4F) : const Color(0xFF9B2226);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(isSale ? Icons.trending_up : Icons.trending_down,
              color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(txn.customerSupplierName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            txn.description?.isNotEmpty == true
                ? txn.description!
                : txn.paymentMethod.name,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${isSale ? '+' : '-'}KES ${txn.amount.toStringAsFixed(0)}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color)),
          Text(
            _relativeDate(txn.createdAt),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
          ),
        ]),
      ]),
    );
  }

  String _relativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _EmptyActivity extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD8E8E0)),
        ),
        child: Column(children: [
          Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text('No transactions yet',
              style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Record a sale or purchase to see activity here',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              textAlign: TextAlign.center),
        ]),
      );
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: Color(0xFF2D6A4F), letterSpacing: 1.6));
}

class _FooterStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _FooterStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ]),
      );
}