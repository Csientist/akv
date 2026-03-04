import 'package:flutter/material.dart';
import '../../core/local_db.dart';
import '../../services/sync_service.dart';

class SyncDebugSheet extends StatefulWidget {
  const SyncDebugSheet({super.key});

  @override
  State<SyncDebugSheet> createState() => _SyncDebugSheetState();
}

class _SyncDebugSheetState extends State<SyncDebugSheet> {
  Future<List<Map<String, dynamic>>> _fetchQueue() async {
    return await LocalDb.instance.getPendingQueue();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
         Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Sync Diagnostics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  // NEW: The Revive Button
                  IconButton(
                    icon: const Icon(Icons.restore, color: Colors.orange),
                    tooltip: 'Revive Failed Items',
                    onPressed: () async {
                      await LocalDb.instance.resetFailedQueue();
                      setState(() {}); // Rebuild UI to show them as pending again
                    },
                  ),
                  // EXISTING: The Sync Button
                  IconButton(
                    icon: const Icon(Icons.sync, color: Colors.blue),
                    tooltip: 'Force Sync Now',
                    onPressed: () {
                      SyncService().processQueue();
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() {}); 
                      });
                    },
                  ),
                ],
              )
            ],
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchQueue(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final queue = snapshot.data ?? [];
                
                if (queue.isEmpty) {
                  return const Center(child: Text('Queue is completely empty! 🎉'));
                }

                return ListView.builder(
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    final isPoisoned = (item['retry_count'] as int? ?? 0) >= 5;

                    return Card(
                      color: isPoisoned ? Colors.red.shade50 : Colors.white,
                      child: ListTile(
                        leading: Icon(
                          isPoisoned ? Icons.error_outline : Icons.cloud_upload_outlined,
                          color: isPoisoned ? Colors.red : Colors.blue,
                        ),
                        title: Text('${item['table_name']}'),
                        subtitle: Text('Record ID: ${item['record_id']}'),
                        trailing: Text(
                          'Retries: ${item['retry_count'] ?? 0}',
                          style: TextStyle(
                            color: isPoisoned ? Colors.red : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}