// lib/features/herd/presentation/herd_screen.dart

import 'dart:async';
import 'package:akv/data/repositories/repositories.dart';
import 'package:flutter/material.dart';
import '../../../data/models/models.dart';
import '../../../services/app_refresh_service.dart';
import 'widgets/asset_list_tab.dart';
import 'sheets/add_asset_sheet.dart';

class HerdManagementScreen extends StatefulWidget {
  const HerdManagementScreen({super.key});

  @override
  State<HerdManagementScreen> createState() => _HerdManagementScreenState();
}

class _HerdManagementScreenState extends State<HerdManagementScreen> with SingleTickerProviderStateMixin {
  final _repo = HerdRepository();
  late TabController _tabController;
  late Future<List<Asset>> _livestockFuture;
  late Future<List<Asset>> _cropFuture;
  StreamSubscription<void>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _tabController   = TabController(length: 2, vsync: this);
    _livestockFuture = _repo.getActiveAssets(AssetCategory.livestock);
    _cropFuture      = _repo.getActiveAssets(AssetCategory.crop);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshSub = AppRefreshService.instance.ticks.listen((_) {
        if (mounted) _refresh();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshSub?.cancel();
    super.dispose();
  }

  void _refresh() {
    final livestock = _repo.getActiveAssets(AssetCategory.livestock);
    final crop      = _repo.getActiveAssets(AssetCategory.crop);
    if (mounted) {
      setState(() {
        _livestockFuture = livestock;
        _cropFuture      = crop;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 56),
              title: Column(
                mainAxisSize: MainAxisSize.min, 
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text('Herd', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: -0.5)),
                  Text('Livestock & Crops', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.outline)),
                ]
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.15)))),
                child: TabBar(
                  controller: _tabController,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.outline,
                  indicatorColor: scheme.primary,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: const [Tab(text: 'Livestock'), Tab(text: 'Crops')],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            AssetListTab(future: _livestockFuture, category: AssetCategory.livestock, onRefresh: _refresh, repo: _repo),
            AssetListTab(future: _cropFuture, category: AssetCategory.crop, onRefresh: _refresh, repo: _repo),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2D6A4F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Register', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AddAssetSheet(
            onSaved: (a) async { 
              await _repo.saveAsset(a); 
              _refresh(); 
            }
          ),
        ),
      ),
    );
  }
}