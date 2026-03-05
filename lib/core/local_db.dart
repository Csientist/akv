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
      version: 2, // Bumped: partial payments + enum casing migration
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // ── Schema ─────────────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {

    // ── PILLAR A: Ledger ──────────────────────────────────────────────────────
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
                        'active','sold','deceased'
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
        category      TEXT NOT NULL DEFAULT 'feed' CHECK(category IN (
                        'feed','medicine','equipment','seed','other'
                      )),
        quantity      REAL NOT NULL DEFAULT 0.0,
        unit          TEXT NOT NULL CHECK(unit IN (
                        'kg','litres','bags','pieces','vials'
                      )),
        reorder_level REAL NOT NULL DEFAULT 0.0,
        notes         TEXT,
        created_by    TEXT NOT NULL,
        created_at    TEXT NOT NULL
      )
    ''');

    // ── PILLAR D: Financials ──────────────────────────────────────────────────
    // amount_paid tracks collected instalments for partial payment support.
    await db.execute('''
      CREATE TABLE financials (
        transaction_id         TEXT PRIMARY KEY,
        transaction_type       TEXT NOT NULL DEFAULT 'sale' CHECK(transaction_type IN (
                                 'sale','purchase'
                               )),
        customer_supplier_name TEXT NOT NULL,
        payment_method         TEXT NOT NULL CHECK(payment_method IN (
                                 'mpesa','cash','bank'
                               )),
        payment_status         TEXT NOT NULL DEFAULT 'paid' CHECK(payment_status IN (
                                 'paid','pending','failed'
                               )),
        amount                 REAL NOT NULL DEFAULT 0.0,
        amount_paid            REAL NOT NULL DEFAULT 0.0,
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

    // ── PILLAR E: Partial Payments ────────────────────────────────────────────
    // Each row is one payment instalment on a sale.
    await db.execute('''
      CREATE TABLE partial_payments (
        payment_id          TEXT PRIMARY KEY,
        transaction_id      TEXT NOT NULL,
        amount              REAL NOT NULL,
        method              TEXT NOT NULL CHECK(method IN ('mpesa','cash','bank')),
        mpesa_receipt       TEXT,
        checkout_request_id TEXT,
        notes               TEXT,
        created_by          TEXT NOT NULL,
        created_at          TEXT NOT NULL,
        FOREIGN KEY (transaction_id) REFERENCES financials(transaction_id)
      )
    ''');

    // ── Asset Events ──────────────────────────────────────────────────────────
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
        session     TEXT NOT NULL CHECK(session IN ('am','pm','full')),
        recorded_at TEXT NOT NULL,
        notes       TEXT,
        created_by  TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        FOREIGN KEY (asset_id) REFERENCES assets(asset_id)
      )
    ''');

    // ── Auth Config (never synced) ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE auth_config (
        id              INTEGER PRIMARY KEY CHECK(id = 1),
        pin_hash        TEXT NOT NULL,
        created_at      TEXT NOT NULL,
        last_changed_at TEXT NOT NULL
      )
    ''');

    // ── Sync Queue ────────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE sync_queue (
        queue_id      INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id     TEXT NOT NULL,
        table_name    TEXT NOT NULL,
        operation     TEXT NOT NULL DEFAULT 'CREATE' CHECK(operation IN ('CREATE','UPDATE','DELETE')),
        status        TEXT NOT NULL DEFAULT 'pending' CHECK(status IN (
                        'pending','processing','failed'
                      )),
        retry_count   INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        created_at    TEXT NOT NULL
      )
    ''');

    await _createIndices(db);
  }

  // ── Migration v1 → v2 ─────────────────────────────────────────────────────
  // Adds amount_paid to financials and creates partial_payments table.
  // Also relaxes CHECK constraints so old rows (SCREAMING_CASE) still parse —
  // the app's fromMap() normalises to lowercase via .toLowerCase().
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add amount_paid column (defaults to 0 for all existing rows)
      await db.execute(
        'ALTER TABLE financials ADD COLUMN amount_paid REAL NOT NULL DEFAULT 0.0',
      );

      // Create partial_payments table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS partial_payments (
          payment_id          TEXT PRIMARY KEY,
          transaction_id      TEXT NOT NULL,
          amount              REAL NOT NULL,
          method              TEXT NOT NULL,
          mpesa_receipt       TEXT,
          checkout_request_id TEXT,
          notes               TEXT,
          created_by          TEXT NOT NULL,
          created_at          TEXT NOT NULL,
          FOREIGN KEY (transaction_id) REFERENCES financials(transaction_id)
        )
      ''');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_partial_txn ON partial_payments(transaction_id)',
      );
    }
  }

  Future<void> _createIndices(Database db) async {
    await db.execute('CREATE INDEX idx_ledger_status    ON ledger_entries(status)');
    await db.execute('CREATE INDEX idx_ledger_source    ON ledger_entries(source_id)');
    await db.execute('CREATE INDEX idx_ledger_user      ON ledger_entries(created_by)');
    await db.execute('CREATE INDEX idx_assets_tag       ON assets(tag_name)');
    await db.execute('CREATE INDEX idx_assets_user      ON assets(created_by)');
    await db.execute('CREATE INDEX idx_inventory_low    ON inventory(quantity, reorder_level)');
    await db.execute('CREATE INDEX idx_inventory_user   ON inventory(created_by)');
    await db.execute('CREATE INDEX idx_financials_user  ON financials(created_by)');
    await db.execute('CREATE INDEX idx_financials_mpesa ON financials(checkout_request_id)');
    await db.execute('CREATE INDEX idx_financials_status ON financials(payment_status)');
    await db.execute('CREATE INDEX idx_events_asset     ON asset_events(asset_id, recorded_at)');
    await db.execute('CREATE INDEX idx_events_user      ON asset_events(created_by)');
    await db.execute('CREATE INDEX idx_milk_asset       ON milk_logs(asset_id, recorded_at)');
    await db.execute('CREATE INDEX idx_milk_user        ON milk_logs(created_by)');
    await db.execute('CREATE INDEX idx_sync_status      ON sync_queue(status)');
    await db.execute('CREATE INDEX idx_partial_txn      ON partial_payments(transaction_id)');
  }

  // ── Sync Queue Helpers ─────────────────────────────────────────────────────

  Future<void> addToQueue(
    Transaction txn, {
    required String recordId,
    required String tableName,
    String operation = 'CREATE',
  }) async {
    await txn.insert('sync_queue', {
      'record_id':   recordId,
      'table_name':  tableName,
      'operation':   operation,
      'status':      'pending',
      'retry_count': 0,
      'created_at':  DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingQueue() async {
    final db  = await database;
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
    final db         = await database;
    final nextRetry  = currentRetry + 1;
    final backoff    = (1 << nextRetry).clamp(2, 3600);
    final nextRetryAt = DateTime.now()
        .add(Duration(seconds: backoff))
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

  Future<List<Map<String, dynamic>>> getMyFinancials({int limit = 50}) async {
    final db     = await database;
    final userId = SessionManager.instance.currentUserId;
    return db.query(
      'financials',
      where: 'created_by = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<double> getMyTotalSales() async {
    final db     = await database;
    final userId = SessionManager.instance.currentUserId;
    final result = await db.rawQuery('''
      SELECT SUM(amount) as total 
      FROM financials 
      WHERE transaction_type = 'sale' 
        AND created_by = ? 
        AND payment_status != 'failed'
    ''', [userId]);
    return (result.first['total'] as double?) ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getMyActiveAssets() async {
    final db     = await database;
    final userId = SessionManager.instance.currentUserId;
    return db.query(
      'assets',
      where: "status = 'active' AND created_by = ?",
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getMyInventory() async {
    final db     = await database;
    final userId = SessionManager.instance.currentUserId;
    return db.query(
      'inventory',
      where: 'created_by = ?',
      whereArgs: [userId],
      orderBy: 'item_name ASC',
    );
  }
}