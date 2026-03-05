import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import '../core/appwrite_client.dart';
import '../core/logger.dart';

// ── Result type ───────────────────────────────────────────────────────────────
// Gives callers structured feedback instead of a bare nullable String.

class MpesaResult {
  final bool success;
  final String? checkoutRequestId;
  final String? merchantRequestId;
  final String? customerMessage; // shown directly to farmer
  final String? error;           // human-readable failure reason

  const MpesaResult._({
    required this.success,
    this.checkoutRequestId,
    this.merchantRequestId,
    this.customerMessage,
    this.error,
  });

  factory MpesaResult.ok({
    required String checkoutRequestId,
    required String merchantRequestId,
    String? customerMessage,
  }) => MpesaResult._(
        success: true,
        checkoutRequestId: checkoutRequestId,
        merchantRequestId: merchantRequestId,
        customerMessage: customerMessage,
      );

  factory MpesaResult.fail(String error) =>
      MpesaResult._(success: false, error: error);
}

// ── Service ───────────────────────────────────────────────────────────────────

class MpesaService {
  static final MpesaService instance = MpesaService._internal();
  MpesaService._internal();

  /// The Appwrite Function ID from your Appwrite Console.
  /// Set this once here — used by both initiatePayment calls.
  static const _stkFunctionId = '69a7e7520029ca740155';

  // ── Phone formatting ───────────────────────────────────────────────────────
  // Go function also sanitizes, but we do it here too so the log is clean
  // and we can reject obviously bad numbers before making a network call.

  String? _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    String formatted;
    if (digits.startsWith('254') && digits.length == 12) {
      formatted = digits;
    } else if (digits.startsWith('0') && digits.length == 10) {
      formatted = '254${digits.substring(1)}';
    } else if (digits.length == 9) {
      formatted = '254$digits';
    } else {
      return null; // unrecognised format
    }
    // Final sanity check
    if (!RegExp(r'^254\d{9}$').hasMatch(formatted)) return null;
    return formatted;
  }

  // ── STK Push ───────────────────────────────────────────────────────────────

  Future<MpesaResult> initiatePayment({
    required String phone,
    required double amount,
    required String transactionId, // your financials.transaction_id
  }) async {
    // 1. Validate + format phone locally first
    final formatted = _formatPhone(phone);
    if (formatted == null) {
      return MpesaResult.fail(
          'Invalid phone number. Use format 07XXXXXXXX or 254XXXXXXXXX.');
    }

    if (amount < 1) {
      return MpesaResult.fail('Amount must be at least KES 1.');
    }

    Log.i('[M-PESA] STK Push → $formatted | KES ${amount.toInt()} | ref: $transactionId');

    try {
      final execution = await AppwriteClient.instance.functions.createExecution(
        functionId: _stkFunctionId,
        body: jsonEncode({
          'phone_number':      formatted,
          'amount':            amount.toInt(), // Daraja requires integer
          'account_reference': transactionId,
        }),
        // Don't await — we want the function to run and Safaricom to callback
        xasync: false,
      );

      // 2. Parse the function's response body
      final rawBody = execution.responseBody;
      if (rawBody.isEmpty) {
        Log.i('[M-PESA] Empty response body from function');
        return MpesaResult.fail('No response from payment server.');
      }

      final Map<String, dynamic> response;
      try {
        response = jsonDecode(rawBody) as Map<String, dynamic>;
      } catch (_) {
        Log.i('[M-PESA] Non-JSON response: $rawBody');
        return MpesaResult.fail('Unexpected response from payment server.');
      }

      // 3. Our Go function returns { success, checkout_request_id, ... }
      //    (snake_case — not Safaricom's raw PascalCase)
      if (response['success'] == true) {
        final checkoutId  = response['checkout_request_id'] as String? ?? '';
        final merchantId  = response['merchant_request_id'] as String? ?? '';
        final message     = response['customer_message'] as String?
            ?? 'Please enter your M-PESA PIN on your phone.';

        Log.i('[M-PESA] STK sent. CheckoutID: $checkoutId');
        return MpesaResult.ok(
          checkoutRequestId: checkoutId,
          merchantRequestId: merchantId,
          customerMessage:   message,
        );
      }

      // 4. Go function returned { success: false, error, code }
      final errMsg = response['error'] as String?
          ?? 'Payment request failed. Try again.';
      Log.e('[M-PESA] Function returned error: $errMsg');
      return MpesaResult.fail(errMsg);

    } on AppwriteException catch (e) {
      Log.e('[M-PESA] Appwrite error: ${e.message} (code: ${e.code})');
      // Surface actionable messages for known codes
      final msg = switch (e.code) {
        404 => 'Payment function not found. Contact support.',
        429 => 'Too many requests. Please wait a moment.',
        503 => 'Payment service temporarily unavailable.',
        _   => 'Payment service error (${e.code}): ${e.message}',
      };
      return MpesaResult.fail(msg);

    } catch (e) {
      Log.e('[M-PESA] Unexpected error: $e');
      return MpesaResult.fail('Unexpected error. Please try again.');
    }
  }
}