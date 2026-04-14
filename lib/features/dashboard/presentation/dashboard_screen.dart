// lib/features/dashboard/presentation/dashboard_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/repositories.dart';
import '../../../services/app_refresh_service.dart';
import '../../../services/sync_service.dart';
import '../../../shared/widgets/shared_widgets.dart';

import 'widgets/sync_banner.dart';
import 'widgets/net_position_card.dart';
import 'widgets/stat_card.dart';
import 'widgets/monthly_summary_card.dart';
import 'widgets/recent_activity_list.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _repo = DashboardRepository();

  DashboardSummary? _data;
  MonthlySummary? _monthlyData;
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
      final futures = await Future.wait([
        _repo.getDashboardSummary(),
        _repo.getMonthlySummary(),
      ]);
      
      if (mounted) {
        setState(() { 
          _data = futures[0] as DashboardSummary; 
          _monthlyData = futures[1] as MonthlySummary;
          _loading = false; 
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

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
          if (_loading && _data != null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2D6A4F)),
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
    if ((_data == null || _monthlyData == null) && _loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)));
    }

    if ((_data == null || _monthlyData == null) && _error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('Could not load data', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }

    final s = _data!;
    final ms = _monthlyData!;

    return RefreshIndicator(
      color: const Color(0xFF2D6A4F),
      onRefresh: _syncAndLoad,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          SyncBanner(pendingCount: s.pendingSyncCount),
          const SizedBox(height: 20),

          NetPositionCard(summary: s),
          const SizedBox(height: 20),

          const SectionLabel('Quick Stats'),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              StatCard(
                icon: Icons.trending_up,
                label: 'This Month',
                value: _fmt(s.totalSalesThisMonth),
                color: const Color(0xFF2D6A4F),
              ),
              StatCard(
                icon: Icons.hourglass_top_outlined,
                label: 'Outstanding',
                value: s.totalOutstanding == 0 ? 'All paid ✓' : _fmt(s.totalOutstanding),
                color: s.totalOutstanding > 0 ? Colors.orange.shade700 : const Color(0xFF2D6A4F),
                alert: s.totalOutstanding > 0,
              ),
              StatCard(
                icon: Icons.pets,
                label: 'Livestock',
                value: '${s.livestockCount} head',
                color: const Color(0xFF2D6A4F),
              ),
              StatCard(
                icon: Icons.inventory_2_outlined,
                label: 'Low Stock',
                value: s.lowStockCount == 0 ? 'All good ✓' : '${s.lowStockCount} item${s.lowStockCount > 1 ? 's' : ''}',
                color: s.lowStockCount > 0 ? Colors.orange.shade700 : const Color(0xFF2D6A4F),
                alert: s.lowStockCount > 0,
              ),
            ],
          ),
          const SizedBox(height: 24),

          Row(children: [
            const SectionLabel('Monthly Performance'),
            const Spacer(),
            Text('Auto-calculated', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 12),
          MonthlySummaryCard(summary: ms),
          const SizedBox(height: 24),

          RecentActivityList(summary: s),
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