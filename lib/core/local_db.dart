import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../services/session_manager.dart';

class LocalDb {
  static final LocalDb instance = LocalDb._internal();
  LocalDb._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'farm_app.db');
    return await openDatabase(
      path,
      version: 1, // Fresh start — no migration history needed
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // ── Schema ─────────────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {

    // ── PILLAR A: Ledger (Append-Only Truth) ──────────────────────────────────
    await db.execute('''
      CREATE TABLE ledger_entries (
        event_id   TEXT PRIMARY KEY,
        type       TEXT NOT NULL CHECK(type IN (
                     'sale','purchase','herdUpdate','inventoryAdjust'
                   )),
        source_id  TEXT NOT NULL,
        amount     REAL NOT NULL DEFAULT 0.0,
        status     TEXT NOT NULL DEFAULT 'pending' CHECK(status IN (
                     'pending','completed','failed'
                   )),
        metadata   TEXT,
        created_by TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // ── PILLAR B: Assets ──────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE assets (
        asset_id      TEXT PRIMARY KEY,
        tag_name      TEXT NOT NULL DEFAULT '',
        category      TEXT NOT NULL CHECK(category IN ('livestock','crop')),
        breed_type    TEXT NOT NULL,
        status        TEXT NOT NULL DEFAULT 'active' CHECK(status IN (
                        'active','SOLD','DECEASED'
                      )),
        weight_kg     REAL,
        date_of_birth TEXT,
        health_notes  TEXT,
        last_event_id TEXT,
        created_by    TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        FOREIGN KEY (last_event_id) REFERENCES ledger_entries(event_id)
      )
    ''');

    // ── PILLAR C: Inventory ───────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE inventory (
        item_id       TEXT PRIMARY KEY,
        item_name     TEXT NOT NULL,
        category      TEXT NOT NULL DEFAULT 'FEED' CHECK(category IN (
                        'FEED','MEDICINE','EQUIPMENT','SEED','OTHER'
                      )),
        quantity      REAL NOT NULL DEFAULT 0.0,
        unit          TEXT NOT NULL CHECK(unit IN (
                        'KG','LITRES','BAGS','PIECES','VIALS'
                      )),
        reorder_level REAL NOT NULL DEFAULT 0.0,
        notes         TEXT,
        created_by    TEXT NOT NULL,
        created_at    TEXT NOT NULL
      )
    ''');

    // ── PILLAR D: Financials (Sales & Purchases) ──────────────────────────────
    await db.execute('''
      CREATE TABLE financials (
        transaction_id         TEXT PRIMARY KEY,
        transaction_type       TEXT NOT NULL DEFAULT 'sale' CHECK(transaction_type IN (
                                 'sale','purchase'
                               )),
        customer_supplier_name TEXT NOT NULL,
        payment_method         TEXT NOT NULL CHECK(payment_method IN (
                                 'MPESA','CASH','BANK'
                               )),
        payment_status         TEXT NOT NULL DEFAULT 'PAID' CHECK(payment_status IN (
                                 'PAID','PENDING','FAILED'
                               )),
        amount                 REAL NOT NULL DEFAULT 0.0,
        description            TEXT,
        is_kra_certified       INTEGER NOT NULL DEFAULT 0,
        kra_reference          TEXT,
        checkout_request_id    TEXT,
        mpesa_receipt          TEXT,
        event_id               TEXT,
        created_by             TEXT NOT NULL,
        created_at             TEXT NOT NULL,
        FOREIGN KEY (event_id) REFERENCES ledger_entries(event_id)
      )
    ''');

    // ── Asset Events (Herd Activity Log) ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE asset_events (
        event_id    TEXT PRIMARY KEY,
        asset_id    TEXT NOT NULL,
        event_type  TEXT NOT NULL,
        notes       TEXT,
        metadata    TEXT,
        recorded_at TEXT NOT NULL,
        created_by  TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        FOREIGN KEY (asset_id) REFERENCES assets(asset_id)
      )
    ''');

    // ── Milk Logs ─────────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE milk_logs (
        log_id      TEXT PRIMARY KEY,
        asset_id    TEXT NOT NULL,
        litres      REAL NOT NULL,
        session     TEXT NOT NULL CHECK(session IN ('AM','PM','FULL')),
        recorded_at TEXT NOT NULL,
        notes       TEXT,
        created_by  TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        FOREIGN KEY (asset_id) REFERENCES assets(asset_id)
      )
    ''');

    // ── Auth Config (local PIN only — never synced) ───────────────────────────
    await db.execute('''
      CREATE TABLE auth_config (
        id              INTEGER PRIMARY KEY CHECK(id = 1),
        pin_hash        TEXT NOT NULL,
        created_at      TEXT NOT NULL,
        last_changed_at TEXT NOT NULL
      )
    ''');

    // ── Sync Queue (Transactional Outbox) ─────────────────────────────────────
    await db.execute('''
      CREATE TABLE sync_queue (
        queue_id      INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id     TEXT NOT NULL,
        table_name    TEXT NOT NULL,
        operation     TEXT NOT NULL CHECK(operation IN ('CREATE','UPDATE','DELETE')),
        status        TEXT NOT NULL DEFAULT 'pending' CHECK(status IN (
                        'pending','processing','failed'
                      )),
        retry_count   INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        created_at    TEXT NOT NULL
      )
    ''');

    // ── Indices ───────────────────────────────────────────────────────────────
    await db.execute('CREATE INDEX idx_ledger_status   ON ledger_entries(status)');
    await db.execute('CREATE INDEX idx_ledger_source   ON ledger_entries(source_id)');
    await db.execute('CREATE INDEX idx_ledger_user     ON ledger_entries(created_by)');
    await db.execute('CREATE INDEX idx_assets_tag      ON assets(tag_name)');
    await db.execute('CREATE INDEX idx_assets_user     ON assets(created_by)');
    await db.execute('CREATE INDEX idx_inventory_low   ON inventory(quantity, reorder_level)');
    await db.execute('CREATE INDEX idx_inventory_user  ON inventory(created_by)');
    await db.execute('CREATE INDEX idx_financials_user ON financials(created_by)');
    await db.execute('CREATE INDEX idx_financials_mpesa ON financials(checkout_request_id)');
    await db.execute('CREATE INDEX idx_events_asset    ON asset_events(asset_id, recorded_at)');
    await db.execute('CREATE INDEX idx_events_user     ON asset_events(created_by)');
    await db.execute('CREATE INDEX idx_milk_asset      ON milk_logs(asset_id, recorded_at)');
    await db.execute('CREATE INDEX idx_milk_user       ON milk_logs(created_by)');
    await db.execute('CREATE INDEX idx_sync_status     ON sync_queue(status)');
  }

  // ── Queue Helpers ──────────────────────────────────────────────────────────

  Future<void> addToQueue(
    Transaction txn, {
    required String recordId,
    required String tableName,
    String operation = 'CREATE',
  }) async {
    await txn.insert('sync_queue', {
      'record_id':  recordId,
      'table_name': tableName,
      'operation':  operation,
      'status':     'pending',
      'retry_count': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingQueue() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.query(
      'sync_queue',
      where: "status = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [now],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> removeFromQueue(int queueId) async {
    final db = await database;
    await db.delete('sync_queue', where: 'queue_id = ?', whereArgs: [queueId]);
  }

  /// Exponential backoff: 2s → 4s → 8s … capped at 1 hour.
  Future<void> markQueueRetry(int queueId, int currentRetry) async {
    final db = await database;
    final nextRetry = currentRetry + 1;
    final backoffSeconds = (1 << nextRetry).clamp(2, 3600);
    final nextRetryAt = DateTime.now()
        .add(Duration(seconds: backoffSeconds))
        .toIso8601String();
    await db.update(
      'sync_queue',
      {
        'retry_count':   nextRetry,
        'next_retry_at': nextRetryAt,
        'status':        nextRetry >= 10 ? 'failed' : 'pending',
      },
      where: 'queue_id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> updateQueueStatus(int queueId, String status) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': status},
      where: 'queue_id = ?',
      whereArgs: [queueId],
    );
  }

  /// Resets all failed/stuck queue items back to pending so they can retry.
  Future<void> resetFailedQueue() async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 'pending', 'retry_count': 0, 'next_retry_at': null},
      where: "status = 'failed' OR retry_count >= 5",
    );
  }

  Future<void> close() async => (await database).close();

  // ── Dashboard & UI Queries ─────────────────────────────────────────────────

  /// Fetch only the financials created by the currently logged-in user
  Future<List<Map<String, dynamic>>> getMyFinancials({int limit = 50}) async {
    final db = await database;
    final userId = SessionManager.instance.currentUserId;

    return db.query(
      'financials',
      where: 'created_by = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC', // Newest first
      limit: limit,
    );
  }

  /// Calculate total sales for the current user (Perfect for the Dashboard)
  Future<double> getMyTotalSales() async {
    final db = await database;
    final userId = SessionManager.instance.currentUserId;

    final result = await db.rawQuery('''
      SELECT SUM(amount) as total 
      FROM financials 
      WHERE transaction_type = 'sale' 
        AND created_by = ? 
        AND payment_status != 'FAILED'
    ''', [userId]);

    final total = result.first['total'] as double?;
    return total ?? 0.0;
  }

  /// Fetch only the active animals/crops this user recorded
  Future<List<Map<String, dynamic>>> getMyActiveAssets() async {
    final db = await database;
    final userId = SessionManager.instance.currentUserId;

    return db.query(
      'assets',
      where: "status = 'active' AND created_by = ?",
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }

  /// Fetch inventory recorded by this user
  Future<List<Map<String, dynamic>>> getMyInventory() async {
    final db = await database;
    final userId = SessionManager.instance.currentUserId;

    return db.query(
      'inventory',
      where: 'created_by = ?',
      whereArgs: [userId],
      orderBy: 'item_name ASC',
    );
  }


}