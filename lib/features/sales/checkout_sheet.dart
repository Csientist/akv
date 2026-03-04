import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/mpesa_service.dart';
import '../../core/local_db.dart';
import '../../services/session_manager.dart';


enum SaleType { cash, mpesaManual, mpesaStk, credit }

class CheckoutSheet extends StatefulWidget {
  final double totalAmount;
  final String customerName;
  final String description;

  const CheckoutSheet({
    super.key,
    required this.totalAmount,
    required this.customerName,
    required this.description,
  });

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  SaleType _selectedType = SaleType.mpesaStk;
  final _inputController = TextEditingController();
  bool _isProcessing = false;

  Future<void> _processSale() async {
    setState(() => _isProcessing = true);

    final eventId = const Uuid().v4();       // ID for Ledger
    final transactionId = const Uuid().v4(); // ID for Financials
    final now = DateTime.now().toIso8601String();
    
    // Get the globally logged-in user ID
    final userId = SessionManager.instance.currentUserId; 

    String? checkoutId;
    String? receiptNumber;
    String paymentMethod = 'CASH';
    String paymentStatus = 'PAID';

    try {
      if (_selectedType == SaleType.mpesaStk) {
        paymentMethod = 'MPESA';
        paymentStatus = 'PENDING';
        
        // 1. Catch the MpesaResult object
        final result = await MpesaService.instance.initiatePayment(
          phone: _inputController.text,
          amount: widget.totalAmount,
          transactionId: transactionId,
        );

        // 2. Check if your custom result was successful
        // (Note: Adjust 'isSuccess', 'checkoutId', and 'errorMessage' 
        // to match whatever you actually named the properties in your MpesaResult class!)
        if (result.success) {
          checkoutId = result.checkoutRequestId; 
        } else {
          throw Exception(result.error ?? 'Failed to send M-PESA prompt.');
        }

        // Just a safety check in case the checkoutId is still somehow null
        if (checkoutId == null || checkoutId.isEmpty) {
          throw Exception('Received an invalid Checkout ID from Safaricom.');
        }
      }
      else if (_selectedType == SaleType.mpesaManual) {
        paymentMethod = 'MPESA';
        receiptNumber = _inputController.text.toUpperCase();
        if (receiptNumber.isEmpty) throw Exception('Please enter the receipt number.');
      } 
      else if (_selectedType == SaleType.credit) {
        paymentMethod = 'CASH'; 
        paymentStatus = 'PENDING';
      }

      // ── ATOMIC SQLITE TRANSACTION ──────────────────────────────────────────
      final db = await LocalDb.instance.database;
      await db.transaction((txn) async {
        
        // 1. Insert the Master Ledger Entry FIRST
        await txn.insert('ledger_entries', {
          'event_id': eventId,
          'type': 'SALE',
          'source_id': transactionId, 
          'amount': widget.totalAmount,
          'status': paymentStatus == 'PAID' ? 'completed' : 'pending',
          'metadata': jsonEncode({
            'description': widget.description, 
            'customer': widget.customerName
          }),
          'created_by': userId, // The Stamp
          'created_at': now,
        });

        // 2. Insert the Financial Record (Linked to the Ledger via event_id)
        await txn.insert('financials', {
          'transaction_id': transactionId,
          'transaction_type': 'SALE',
          'customer_supplier_name': widget.customerName,
          'payment_method': paymentMethod,
          'payment_status': paymentStatus,
          'amount': widget.totalAmount,
          'description': widget.description,
          'checkout_request_id': checkoutId,
          'mpesa_receipt': receiptNumber,
          'event_id': eventId, // THE LINK
          'created_by': userId, // The Stamp
          'created_at': now,
        });

        // 3. Add BOTH to the Sync Queue
        await LocalDb.instance.addToQueue(txn, recordId: eventId, tableName: 'ledger_entries');
        await LocalDb.instance.addToQueue(txn, recordId: transactionId, tableName: 'financials');
      });

      if (mounted) {
        Navigator.pop(context, true); 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_selectedType == SaleType.mpesaStk 
            ? 'Prompt sent! Waiting for customer...' 
            : 'Sale recorded perfectly!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Checkout: Ksh ${widget.totalAmount}', 
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // The Payment Options
          SegmentedButton<SaleType>(
            segments: const [
              ButtonSegment(value: SaleType.mpesaStk, label: Text('Send STK')),
              ButtonSegment(value: SaleType.mpesaManual, label: Text('Receipt')),
              ButtonSegment(value: SaleType.cash, label: Text('Cash')),
              ButtonSegment(value: SaleType.credit, label: Text('Credit')),
            ],
            selected: {_selectedType},
            onSelectionChanged: (Set<SaleType> newSelection) {
              setState(() {
                _selectedType = newSelection.first;
                _inputController.clear();
              });
            },
          ),
          const SizedBox(height: 24),

          // Dynamic Input Field
          if (_selectedType == SaleType.mpesaStk)
            TextField(
              controller: _inputController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Customer Phone Number',
                hintText: '07XX XXX XXX',
                prefixIcon: Icon(Icons.phone_android),
                border: OutlineInputBorder(),
              ),
            )
          else if (_selectedType == SaleType.mpesaManual)
            TextField(
              controller: _inputController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'M-PESA Receipt Number',
                hintText: 'e.g. QWE123RTY',
                prefixIcon: Icon(Icons.receipt_long),
                border: OutlineInputBorder(),
              ),
            )
          else if (_selectedType == SaleType.credit)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade50,
              child: const Text('This sale will be marked as PENDING. The customer owes you this amount.', 
                style: TextStyle(color: Colors.deepOrange)),
            ),

          const SizedBox(height: 24),
          
          // Submit Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: _isProcessing ? null : _processSale,
            child: _isProcessing 
                ? const CircularProgressIndicator(color: Colors.white) 
                : const Text('Confirm Sale', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}