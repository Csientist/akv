// lib/data/repositories/finance_repository.dart

import 'package:uuid/uuid.dart';
import '../../core/local_db.dart';
import '../../services/session_manager.dart';
import '../../services/sync_service.dart';
import '../models/models.dart';

const _uuid = Uuid();

class FinanceRepository {
  final LocalDb _db;
  FinanceRepository({LocalDb? db}) : _db = db ?? LocalDb.instance;

  String get _uid => SessionManager.instance.currentUserId;

  Future<LedgerEntry> recordSale({
    required String sourceId,
    required double amount,
    required Financial financial,
    Map<String, dynamic>? metadata,
  }) async {
    final entry = LedgerEntry(
      eventId:   _uuid.v4(),
      type:      LedgerType.sale,
      sourceId:  sourceId,
      amount:    amount,
      status:    LedgerStatus.pending,
      metadata:  metadata,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await txn.insert('financials',
          financial.copyWith(eventId: entry.eventId, createdBy: _uid).toMap());
      await _db.addToQueue(txn, recordId: entry.eventId,          tableName: 'ledger_entries');
      await _db.addToQueue(txn, recordId: financial.transactionId, tableName: 'financials');
    });
    SyncService().processQueue();
    return entry;
  }

  Future<LedgerEntry> recordPurchase({
    required String sourceId,
    required double amount,
    required Financial financial,
    Map<String, dynamic>? metadata,
  }) async {
    final entry = LedgerEntry(
      eventId:   _uuid.v4(),
      type:      LedgerType.purchase,
      sourceId:  sourceId,
      amount:    amount,
      status:    LedgerStatus.pending,
      metadata:  metadata,
      createdBy: _uid,
      createdAt: DateTime.now(),
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await txn.insert('financials',
          financial.copyWith(eventId: entry.eventId, createdBy: _uid).toMap());
      await _db.addToQueue(txn, recordId: entry.eventId,            tableName: 'ledger_entries');
      await _db.addToQueue(txn, recordId: financial.transactionId,  tableName: 'financials');
    });
    SyncService().processQueue();
    return entry;
  }

  Future<PartialPayment> addPartialPayment({
    required String transactionId,
    required double amount,
    required PaymentMethod method,
    String? mpesaReceipt,
    String? checkoutRequestId,
    String? notes,
  }) async {
    final payment = PartialPayment(
      paymentId:          _uuid.v4(),
      transactionId:      transactionId,
      amount:             amount,
      method:             method,
      mpesaReceipt:       mpesaReceipt,
      checkoutRequestId:  checkoutRequestId,
      notes:              notes,
      createdBy:          _uid,
      createdAt:          DateTime.now(),
    );

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert('partial_payments', payment.toMap());
      await txn.rawUpdate('''
        UPDATE financials
        SET amount_paid = amount_paid + ?,
            payment_status = CASE
              WHEN (amount_paid + ?) >= amount THEN 'paid'
              ELSE 'pending'
            END
        WHERE transaction_id = ?
      ''', [amount, amount, transactionId]);

      await _db.addToQueue(txn, recordId: payment.paymentId, tableName: 'partial_payments');
      await _db.addToQueue(txn, recordId: transactionId, tableName: 'financials', operation: 'UPDATE');
    });

    SyncService().processQueue();
    return payment;
  }

  Future<List<PartialPayment>> getPaymentsForTransaction(String transactionId) async {
    final db   = await _db.database;
    final rows = await db.query(
      'partial_payments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PartialPayment.fromMap).toList();
  }

  Future<List<Financial>> getOutstandingSales() async {
    final db   = await _db.database;
    final rows = await db.query(
      'financials',
      where: "transaction_type = 'sale' AND payment_status = 'pending' AND created_by = ?",
      whereArgs: [_uid],
      orderBy: 'created_at DESC',
    );
    return rows.map(Financial.fromMap).toList();
  }

  Future<List<LedgerEntry>> getRecentLedger({int limit = 50}) async {
    final db   = await _db.database;
    final rows = await db.query(
      'ledger_entries',
      where: 'created_by = ?',
      whereArgs: [_uid],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(LedgerEntry.fromMap).toList();
  }

  Future<List<Financial>> getRecentFinancials({int limit = 50}) async {
    final db   = await _db.database;
    final rows = await db.query(
      'financials',
      where: 'created_by = ?',
      whereArgs: [_uid],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Financial.fromMap).toList();
  }
}