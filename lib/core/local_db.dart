import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
      version: 3,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    // PILLAR A: Ledger (Append-Only Truth)
    await db.execute('''
      CREATE TABLE ledger_entries (
        event_id      TEXT PRIMARY KEY,
        type          TEXT NOT NULL CHECK(type IN ('SALE','PURCHASE','HERD_UPDATE','INVENTORY_ADJUST')),
        source_id     TEXT NOT NULL,
        amount        REAL DEFAULT 0.0,
        status        TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','completed','failed')),
        metadata      TEXT,
        created_at    TEXT NOT NULL
      )
    ''');

    // PILLAR B: Assets — with full animal details
    await db.execute('''
      CREATE TABLE assets (
        asset_id      TEXT PRIMARY KEY,
        tag_name      TEXT NOT NULL DEFAULT '',
        category      TEXT NOT NULL CHECK(category IN ('LIVESTOCK','CROP')),
        breed_type    TEXT NOT NULL,
        status        TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','SOLD','DECEASED')),
        weight_kg     REAL,
        date_of_birth TEXT,            -- ISO8601 date, e.g. '2022-03-15'
        health_notes  TEXT,
        last_event_id TEXT,
        created_at    TEXT NOT NULL,
        FOREIGN KEY (last_event_id) REFERENCES ledger_entries(event_id)
      )
    ''');

    // PILLAR C: Inventory — with category and notes
    await db.execute('''
      CREATE TABLE inventory (
        item_id       TEXT PRIMARY KEY,
        item_name     TEXT NOT NULL,
        category      TEXT NOT NULL DEFAULT 'FEED' CHECK(category IN ('FEED','MEDICINE','EQUIPMENT','SEED','OTHER')),
        quantity      REAL NOT NULL DEFAULT 0.0,
        unit          TEXT NOT NULL CHECK(unit IN ('KG','LITRES','BAGS','PIECES','VIALS')),
        reorder_level REAL NOT NULL DEFAULT 0.0,
        notes         TEXT,
        created_at    TEXT NOT NULL
      )
    ''');

    // PILLAR D: Financials (Sales & Purchases)
    await db.execute('''
      CREATE TABLE financials (
        transaction_id         TEXT PRIMARY KEY,
        transaction_type       TEXT NOT NULL DEFAULT 'SALE' CHECK(transaction_type IN ('SALE','PURCHASE')),
        customer_supplier_name TEXT NOT NULL,
        payment_method         TEXT NOT NULL CHECK(payment_method IN ('MPESA','CASH','BANK')),
        amount                 REAL NOT NULL DEFAULT 0.0,
        description            TEXT,
        is_kra_certified       INTEGER NOT NULL DEFAULT 0,
        kra_reference          TEXT,
        event_id               TEXT,
        created_at             TEXT NOT NULL,
        FOREIGN KEY (event_id) REFERENCES ledger_entries(event_id)
      )
    ''');

    // SYNC QUEUE (Transactional Outbox)
    await db.execute('''
      CREATE TABLE sync_queue (
        queue_id      INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id     TEXT NOT NULL,
        table_name    TEXT NOT NULL,
        operation     TEXT NOT NULL CHECK(operation IN ('CREATE','UPDATE','DELETE')),
        status        TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','processing','failed')),
        retry_count   INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        created_at    TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_ledger_status ON ledger_entries(status)');
    await db.execute('CREATE INDEX idx_ledger_source ON ledger_entries(source_id)');
    await db.execute('CREATE INDEX idx_sync_status   ON sync_queue(status)');
    await db.execute('CREATE INDEX idx_inventory_low ON inventory(quantity, reorder_level)');
    await db.execute('CREATE INDEX idx_assets_tag    ON assets(tag_name)');

    // v3 tables — also created fresh for new installs
    await _createV3Tables(db);
  }

  /// Migrate v1 → v2 → v3 without destroying data.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE assets ADD COLUMN tag_name     TEXT NOT NULL DEFAULT ""');
      await db.execute('ALTER TABLE assets ADD COLUMN weight_kg    REAL');
      await db.execute('ALTER TABLE assets ADD COLUMN date_of_birth TEXT');
      await db.execute('ALTER TABLE assets ADD COLUMN health_notes TEXT');
      await db.execute("ALTER TABLE inventory ADD COLUMN category TEXT NOT NULL DEFAULT 'FEED'");
      await db.execute('ALTER TABLE inventory ADD COLUMN notes TEXT');
      await db.execute("ALTER TABLE financials ADD COLUMN transaction_type TEXT NOT NULL DEFAULT 'SALE'");
      await db.execute('ALTER TABLE financials ADD COLUMN description TEXT');
    }
    if (oldVersion < 3) {
      await _createV3Tables(db);
    }
  }

  Future<void> _createV3Tables(Database db) async {
    // Asset Events — activity log for every animal/crop action
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_events (
        event_id      TEXT PRIMARY KEY,
        asset_id      TEXT NOT NULL,
        event_type    TEXT NOT NULL,
        notes         TEXT,
        metadata      TEXT,
        recorded_at   TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        FOREIGN KEY (asset_id) REFERENCES assets(asset_id)
      )
    ''');

    // Milk Logs — dedicated structured table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS milk_logs (
        log_id        TEXT PRIMARY KEY,
        asset_id      TEXT NOT NULL,
        litres        REAL NOT NULL,
        session       TEXT NOT NULL CHECK(session IN ('AM','PM','FULL')),
        recorded_at   TEXT NOT NULL,
        notes         TEXT,
        FOREIGN KEY (asset_id) REFERENCES assets(asset_id)
      )
    ''');

    // Auth Config — hashed PIN (only ever 1 row)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auth_config (
        id              INTEGER PRIMARY KEY CHECK(id = 1),
        pin_hash        TEXT NOT NULL,
        created_at      TEXT NOT NULL,
        last_changed_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_events_asset ON asset_events(asset_id, recorded_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_milk_asset   ON milk_logs(asset_id, recorded_at)');
  }

  // ── Queue Helpers ──────────────────────────────────────────────────────────

  Future<void> addToQueue(
    Transaction txn, {
    required String recordId,
    required String tableName,
    String operation = 'CREATE',
  }) async {
    await txn.insert('sync_queue', {
      'record_id': recordId,
      'table_name': tableName,
      'operation': operation,
      'status': 'pending',
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

  Future<void> markQueueRetry(int queueId, int currentRetry) async {
    final db = await database;
    final nextRetry = currentRetry + 1;
    final backoffSeconds = (1 << nextRetry).clamp(2, 3600);
    final nextRetryAt = DateTime.now().add(Duration(seconds: backoffSeconds)).toIso8601String();
    await db.update(
      'sync_queue',
      {
        'retry_count': nextRetry,
        'next_retry_at': nextRetryAt,
        'status': nextRetry >= 10 ? 'failed' : 'pending',
      },
      where: 'queue_id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> updateQueueStatus(int queueId, String status) async {
    final db = await database;
    await db.update('sync_queue', {'status': status}, where: 'queue_id = ?', whereArgs: [queueId]);
  }

  Future<void> close() async => (await database).close();

  // The Defibrillator: Resets dead queue items back to pending
  Future<void> resetFailedQueue() async {
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': 'pending',
        'retry_count': 0,
        'next_retry_at': null,
      },
      // Target anything that gave up
      where: "status = 'failed' OR retry_count >= 5", 
    );
  }
}