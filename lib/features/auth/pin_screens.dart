import 'package:flutter/material.dart';
import '../../services/pin_service.dart';

// ── Setup PIN Screen ──────────────────────────────────────────────────────────
// Shown once after first Appwrite login.

class SetupPinScreen extends StatefulWidget {
  final VoidCallback onPinSet;
  const SetupPinScreen({super.key, required this.onPinSet});

  @override
  State<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends State<SetupPinScreen> {
  String _pin = '';
  String _confirm = '';
  bool _confirming = false;
  String? _error;

  void _onKey(String digit) {
    setState(() {
      _error = null;
      if (!_confirming) {
        if (_pin.length < 4) _pin += digit;
        if (_pin.length == 4) _confirming = true;
      } else {
        if (_confirm.length < 4) _confirm += digit;
        if (_confirm.length == 4) _submitPin();
      }
    });
  }

  void _onBackspace() {
    setState(() {
      _error = null;
      if (_confirming) {
        if (_confirm.isNotEmpty) {_confirm = _confirm.substring(0, _confirm.length - 1);}
        else { _confirming = false; _pin = ''; }
      } else {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  Future<void> _submitPin() async {
    if (_pin != _confirm) {
      setState(() { _error = 'PINs do not match. Try again.'; _confirm = ''; _pin = ''; _confirming = false; });
      return;
    }
    await PinService.instance.setPin(_pin);
    widget.onPinSet();
  }

  @override
  Widget build(BuildContext context) {
    final current = _confirming ? _confirm : _pin;
    final label = _confirming ? 'Confirm your PIN' : 'Set a 4-digit PIN';
    final sub = _confirming ? 'Enter the same PIN again' : 'You\'ll use this to unlock the app daily';

    return _PinScaffold(
      label: label,
      sublabel: sub,
      current: current,
      error: _error,
      onKey: _onKey,
      onBackspace: _onBackspace,
      showLogout: false,
    );
  }
}

// ── PIN Unlock Screen ─────────────────────────────────────────────────────────
// Shown on every subsequent launch.

class PinScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const PinScreen({super.key, required this.onUnlocked});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  String? _error;
  int _attempts = 0;

  void _onKey(String digit) {
    if (_pin.length >= 4) return;
    setState(() { _error = null; _pin += digit; });
    if (_pin.length == 4) _verify();
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) setState(() { _pin = _pin.substring(0, _pin.length - 1); _error = null; });
  }

  Future<void> _verify() async {
    final ok = await PinService.instance.verifyPin(_pin);
    if (ok) {
      widget.onUnlocked();
    } else {
      _attempts++;
      setState(() {
        _error = _attempts >= 5
            ? 'Too many attempts. Please wait.'
            : 'Incorrect PIN. Try again.';
        _pin = '';
      });
    }
  }

  Future<void> _logout() async {
    await PinService.instance.logout();
    if (mounted) setState(() {}); // AuthGate will re-check and show login
  }

  @override
  Widget build(BuildContext context) => _PinScaffold(
        label: 'Enter PIN',
        sublabel: 'Unlock Farm Manager',
        current: _pin,
        error: _error,
        onKey: _onKey,
        onBackspace: _onBackspace,
        showLogout: true,
        onLogout: _logout,
      );
}

// ── Shared PIN Pad Widget ─────────────────────────────────────────────────────

class _PinScaffold extends StatelessWidget {
  final String label;
  final String sublabel;
  final String current;
  final String? error;
  final void Function(String) onKey;
  final VoidCallback onBackspace;
  final bool showLogout;
  final VoidCallback? onLogout;

  const _PinScaffold({
    required this.label,
    required this.sublabel,
    required this.current,
    required this.error,
    required this.onKey,
    required this.onBackspace,
    required this.showLogout,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B4332),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    SizedBox(height: constraints.maxHeight * 0.1),
                    const Icon(Icons.grass, color: Colors.white, size: 48),
                    const SizedBox(height: 16),
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(sublabel,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 14)),
                    const SizedBox(height: 40),

                    // PIN dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        final filled = i < current.length;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled ? Colors.white : Colors.transparent,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        );
                      }),
                    ),

                    // Error message
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 20,
                      child: error != null
                          ? Text(error!,
                              style: TextStyle(
                                  color: Colors.red.shade300, fontSize: 13))
                          : null,
                    ),

                    const Spacer(),

                    // Numpad
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        children: [
                          for (final row in [
                            ['1', '2', '3'],
                            ['4', '5', '6'],
                            ['7', '8', '9']
                          ]) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: row
                                  .map((d) =>
                                      _DigitKey(digit: d, onTap: () => onKey(d)))
                                  .toList(),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              showLogout
                                  ? GestureDetector(
                                      onTap: onLogout,
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        alignment: Alignment.center,
                                        child: Text('Log out',
                                            style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.5),
                                                fontSize: 12)),
                                      ),
                                    )
                                  : const SizedBox(width: 72, height: 72),
                              _DigitKey(digit: '0', onTap: () => onKey('0')),
                              GestureDetector(
                                onTap: onBackspace,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.backspace_outlined,
                                      color: Colors.white, size: 24),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitKey extends StatelessWidget {
  final String digit;
  final VoidCallback onTap;
  const _DigitKey({required this.digit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
        ),
        alignment: Alignment.center,
        child: Text(digit,
            style: const TextStyle(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.w500)),
      ),
    );
  }
}