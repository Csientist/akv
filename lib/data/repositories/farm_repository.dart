import 'package:uuid/uuid.dart';
import '../../core/local_db.dart';
import '../../services/sync_service.dart';

class FarmRepository {
  final LocalDb _db = LocalDb.instance;
  final SyncService _sync = SyncService();
  final _uuid = const Uuid();

  // ── Add Livestock / Asset ──────────────────────────────────────────────────
  Future<void> addAsset({
    required String category, // 'livestock' or 'crop'
    required String breedType,
    required String status,
    Map<String, dynamic>? metadata,
  }) async {
    final assetId = _uuid.v4();
    final eventId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    final db = await _db.database;

    await db.transaction((txn) async {
      // 1. Create the Asset Record
      await txn.insert('assets', {
        'asset_id': assetId,
        'category': category,
        'breed_type': breedType,
        'status': status,
        'last_event_id': eventId,
      });

      // 2. Create the Ledger Entry (The Audit Trail)
      await txn.insert('ledger_entries', {
        'event_id': eventId,
        'type': 'LOG',
        'category': 'HERD',
        'asset_id': assetId,
        'status': 'completed',
        'created_at': now,
        'metadata': '{"action": "Initial Registration", "breed": "$breedType"}',
      });

      // 3. Add both to the Sync Queue
      await txn.insert('sync_queue', {
        'record_id': assetId,
        'table_name': 'assets',
        'status': 'pending',
        'retry_count': 0,
        'created_at': now,
      });

      await txn.insert('sync_queue', {
        'record_id': eventId,
        'table_name': 'ledger_entries',
        'status': 'pending',
        'retry_count': 0,
        'created_at': now,
      });
    });

    // Trigger the sync service (non-blocking)
    _sync.processQueue();
  }

  // ── Update Inventory (Restock/Usage) ──────────────────────────────────────
  Future<void> adjustInventory({
    required String itemId,
    required double changeAmount, // Positive for restock, Negative for usage
    required String reason,
  }) async {
    final eventId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final db = await _db.database;

    await db.transaction((txn) async {
      // 1. Update the local inventory count
      await txn.execute(
        'UPDATE inventory SET quantity = quantity + ? WHERE item_id = ?',
        [changeAmount, itemId],
      );

      // 2. Log the event
      await txn.insert('ledger_entries', {
        'event_id': eventId,
        'type': 'ADJUST',
        'category': 'INVENTORY',
        'asset_id': itemId,
        'quantity': changeAmount,
        'status': 'completed',
        'created_at': now,
        'metadata': '{"reason": "$reason"}',
      });

      // 3. Sync the changes
      await txn.insert('sync_queue', {
        'record_id': itemId, 
        'table_name': 'inventory', 
        'status': 'pending', 
        'retry_count': 0,
        'created_at': now,
      });
      
      await txn.insert('sync_queue', {
        'record_id': eventId, 
        'table_name': 'ledger_entries', 
        'status': 'pending', 
        'retry_count': 0,
        'created_at': now,
      });
    });

    _sync.processQueue();
  }
}