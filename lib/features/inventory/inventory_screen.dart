import 'package:flutter/material.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      appBar: AppBar(
        title: const Text('Inventory & Stock', style: TextStyle(fontFamily: 'Lora', fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0,
      ),
      body: Column(
        children: [
          _buildStockAlertBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildInventoryItem("Dairy Meal", "450 kg", 0.8, "High"),
                _buildInventoryItem("Silage", "120 kg", 0.2, "Low"),
                _buildInventoryItem("Vaccines", "14 Vials", 0.5, "Medium"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockAlertBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.orange[50],
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange[800], size: 20),
          const SizedBox(width: 12),
          Text("2 items are below reorder levels", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildInventoryItem(String name, String qty, double progress, String level) {
    Color levelColor = level == "Low" ? Colors.red : (level == "Medium" ? Colors.orange : Colors.green);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E8E0)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(qty, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[900])),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFFF1F8F6),
            color: levelColor,
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text("Stock Level: ", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              Text(level, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: levelColor)),
            ],
          )
        ],
      ),
    );
  }
}