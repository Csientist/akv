import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      appBar: AppBar(
        title: const Text('Farm Manager', 
          style: TextStyle(fontFamily: 'Lora', fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B4332),
        elevation: 0,
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSyncStatusHeader(),
            const SizedBox(height: 24),
            const Text("QUICK STATS", style: _sectionLabelStyle),
            const SizedBox(height: 12),
            _buildStatGrid(),
            const SizedBox(height: 24),
            const Text("RECENT ACTIVITY", style: _sectionLabelStyle),
            _buildActivityList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFD8F3DC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 4, backgroundColor: Color(0xFF2D6A4F)),
          const SizedBox(width: 12),
          const Text("Systems Online", 
            style: TextStyle(color: Color(0xFF2D6A4F), fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF2D6A4F), borderRadius: BorderRadius.circular(20)),
            child: const Text("3 PENDING", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _statCard("Total Sales", "KES 42.5k", Icons.shopping_cart_outlined),
        _statCard("Milk Collected", "142 Litres", Icons.water_drop_outlined),
        _statCard("Herd Health", "98%", Icons.favorite_border),
        _statCard("Inventory", "Low Stock", Icons.warning_amber_rounded),
      ],
    );
  }

  Widget _statCard(String title, String val, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E8E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: const Color(0xFF2D6A4F), size: 20),
          Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF52796F))),
          Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B4332))),
        ],
      ),
    );
  }
  
  Widget _buildActivityList() {
  return ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: 3,
    itemBuilder: (context, index) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFD8F3DC),
              child: Icon(Icons.history, color: Color(0xFF2D6A4F), size: 18),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Milk Sale #882", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text("20L to Nairobi Dairy", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const Spacer(),
            Text("KES 1,200", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
          ],
        ),
      );
    },
  );
}

}

const _sectionLabelStyle = TextStyle(
  fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F), letterSpacing: 1.6);