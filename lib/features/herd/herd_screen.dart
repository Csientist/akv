import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/ledger_entry.dart'; // Assuming Asset models are in here
import '../../data/repositories/ledger_repository.dart';

class HerdManagementScreen extends StatefulWidget {
  const HerdManagementScreen({super.key});

  @override
  State<HerdManagementScreen> createState() => _HerdManagementScreenState();
}

class _HerdManagementScreenState extends State<HerdManagementScreen> {
  final LedgerRepository _repo = LedgerRepository();
  late Future<List<Asset>> _livestockFuture;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _livestockFuture = _repo.getActiveAssets(AssetCategory.LIVESTOCK);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      appBar: AppBar(
        title: const Text('Herd Management', style: TextStyle(fontFamily: 'Lora', fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, 
        elevation: 0,
        foregroundColor: const Color(0xFF1B4332),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2D6A4F),
        onPressed: () => _showAddAnimalDialog(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: FutureBuilder<List<Asset>>(
        future: _livestockFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)));
          }
          
          if (snapshot.hasError) {
            return Center(child: Text("Error loading herd: ${snapshot.error}"));
          }

          final assets = snapshot.data ?? [];
          final totalHead = assets.length;
          // Example calculation: Assuming 'Healthy' or ACTIVE means milking for this basic summary
          final milkingCount = assets.where((a) => a.status == AssetStatus.ACTIVE).length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSummaryCard(totalHead: totalHead, milking: milkingCount, calves: 0),
              const SizedBox(height: 24),
              const Text("LIVESTOCK LIST", 
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F), letterSpacing: 1.6)),
              const SizedBox(height: 12),
              
              if (assets.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(child: Text("No livestock found. Add one to get started.", style: TextStyle(color: Colors.grey))),
                )
              else
                ...assets.map((asset) => _buildAnimalTile(asset)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({required int totalHead, required int milking, required int calves}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4332),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(children: [Text("$totalHead", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), const Text("Total Head", style: TextStyle(color: Colors.white70, fontSize: 12))]),
          Column(children: [Text("$milking", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), const Text("Milking", style: TextStyle(color: Colors.white70, fontSize: 12))]),
          Column(children: [Text("$calves", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), const Text("Calves", style: TextStyle(color: Colors.white70, fontSize: 12))]),
        ],
      ),
    );
  }

  Widget _buildAnimalTile(Asset asset) {
    // Basic status to UI mapping
    final isHealthy = asset.status == AssetStatus.ACTIVE;
    final icon = isHealthy ? Icons.check_circle : Icons.warning_amber_rounded;
    final color = isHealthy ? Colors.green : Colors.orange;
    final statusText = isHealthy ? "Healthy" : "Attention";

    // Truncate UUID for display (e.g., "Cow #a1b2")
    final shortId = asset.assetId.substring(0, 4).toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFF1F8F6), child: Icon(Icons.pets, color: Color(0xFF2D6A4F))),
        title: Text("Tag #$shortId", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(asset.breedType),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            Text(statusText, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  void _showAddAnimalDialog(BuildContext context) {
    String selectedBreed = '';
    AssetCategory category = AssetCategory.LIVESTOCK; 

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom, 
              left: 20, right: 20, top: 20
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Register New Asset", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                DropdownButtonFormField<AssetCategory>(
                  initialValue: category,
                  items: AssetCategory.values.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat == AssetCategory.LIVESTOCK ? "Livestock (Cows/Goats)" : "Crops (Maize/Coffee)"),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setModalState(() => category = v);
                  },
                  decoration: const InputDecoration(labelText: "Asset Category"),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: "Breed / Variety", hintText: "e.g. Friesian or H624 Maize"),
                  onChanged: (v) => selectedBreed = v,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F), 
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (selectedBreed.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please enter a breed or variety."))
                      );
                      return;
                    }

                    // 1. Construct the Asset
                    final newAsset = Asset(
                      assetId: const Uuid().v4(),
                      category: category,
                      breedType: selectedBreed,
                      status: AssetStatus.ACTIVE,
                      createdAt: DateTime.now().toUtc(),
                    );

                    // 2. Save using the LedgerRepository
                    await _repo.saveAsset(newAsset);

                    // 3. Close the dialog safely
                    if (!context.mounted) return;
                    Navigator.pop(context);

                    // 4. Trigger UI refresh to show the new animal instantly
                    _refreshData();
                  },
                  child: const Text("Confirm Registration", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        }
      ),
    );
  }
}