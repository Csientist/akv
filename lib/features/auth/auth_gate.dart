import 'package:flutter/material.dart';
import '../../services/app_refresh_service.dart';
import '../../services/mpesa_listener_service.dart';
import '../../services/pin_service.dart';
import '../../services/session_manager.dart';
import 'login_screen.dart';
import 'pin_screens.dart';

/// Shown as the app's home. Decides the correct auth screen based on state.
///
/// Flow:
///   No session  → LoginScreen (Appwrite email/password)
///   Session + no PIN → SetupPinScreen (first time)
///   Session + PIN    → PinScreen (fast daily unlock)
class AuthGate extends StatefulWidget {
  final Widget child; // The main app shell shown after auth
  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _AuthState _state = _AuthState.loading;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Try to restore the Appwrite session and populate SessionManager.
    // This handles both "online first launch" and "offline subsequent launch".
    final restored = await SessionManager.instance.restore();
    final hasPin   = await PinService.instance.hasPin();

    if (!mounted) return;

    setState(() {
      if (!restored)       {_state = _AuthState.needsLogin;}
      else if (!hasPin)    {_state = _AuthState.needsPin;}
      else                {_state = _AuthState.needsUnlock;}
    });
  }

  void _onLoggedIn() => setState(() => _state = _AuthState.needsPin);
  void _onPinSet()   => setState(() => _state = _AuthState.unlocked);
  void _onUnlocked() {
    MpesaListenerService.instance.start();
    AppRefreshService.instance.start(); // fires an immediate tick → sync + UI load
    setState(() => _state = _AuthState.unlocked);
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _AuthState.loading:
        return const _SplashScreen();
      case _AuthState.needsLogin:
        return LoginScreen(onLoggedIn: _onLoggedIn);
      case _AuthState.needsPin:
        return SetupPinScreen(onPinSet: _onPinSet);
      case _AuthState.needsUnlock:
        return PinScreen(onUnlocked: _onUnlocked);
      case _AuthState.unlocked:
        return widget.child;
    }
  }
}

enum _AuthState { loading, needsLogin, needsPin, needsUnlock, unlocked }

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF1B4332),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.grass, size: 64, color: Colors.white),
            SizedBox(height: 16),
            Text('Farm Manager',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Lora')),
            SizedBox(height: 32),
            CircularProgressIndicator(color: Color(0xFF52B788)),
          ]),
        ),
      );
}