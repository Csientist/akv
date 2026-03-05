import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import '../../core/appwrite_client.dart';
import '../../services/pin_service.dart';
import '../../services/session_manager.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _phoneCtrl  = TextEditingController(); // Swapped to phone controller
  final _passCtrl   = TextEditingController();
  bool _obscure     = true;
  bool _loading     = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      // 1. Sanitize the phone input (remove spaces, dashes, etc.)
      final rawPhone = _phoneCtrl.text.trim();
      final cleanPhone = rawPhone.replaceAll(RegExp(r'[^\d+]'), ''); 
      
      // 2. Construct the dummy email
      final dummyEmail = '$cleanPhone@farm.local';

      final account = Account(AppwriteClient.instance.client);
      final session = await account.createEmailPasswordSession(
        email: dummyEmail, // Pass the dummy email to Appwrite
        password: _passCtrl.text,
      );

      await PinService.instance.saveSession(session.$id);

      // Fetch the user profile and cache it in SessionManager so every
      // subsequent DB write can stamp created_by without an Appwrite call.
      final user = await account.get();
      SessionManager.instance.setUser(user);

      // Persist the real user ID to secure storage so offline restarts can
      // restore created_by correctly without hitting Appwrite.
      await PinService.instance.saveUserId(user.$id, name: user.name);

      widget.onLoggedIn();
    } on AppwriteException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Connection failed. Check your internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(AppwriteException e) {
    switch (e.code) {
      case 401: return 'Incorrect phone number or password.';
      case 429: return 'Too many attempts. Please wait a moment.';
      default:  return e.message ?? 'Login failed. Try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // Logo / branding
                const Center(
                  child: Column(children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Color(0xFF1B4332),
                      child: Icon(Icons.grass, color: Colors.white, size: 36),
                    ),
                    SizedBox(height: 16),
                    Text('Farm Manager',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Lora',
                            color: Color(0xFF1B4332))),
                    SizedBox(height: 6),
                    Text('Sign in to your account',
                        style: TextStyle(color: Color(0xFF52796F), fontSize: 14)),
                  ]),
                ),
                const SizedBox(height: 48),

                // Error banner
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // Phone Number Field
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone, // Triggers the numeric keypad
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: 'e.g. 254700000000',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter your phone number';
                    // Strip non-digits to check length
                    final digitsOnly = v.replaceAll(RegExp(r'\D'), '');
                    if (digitsOnly.length < 9) return 'Enter a valid phone number';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Password Field
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 28),

                // Login button
                ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Sign In',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 24),

                Center(
                  child: Text(
                    'Account managed via Appwrite Console',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}