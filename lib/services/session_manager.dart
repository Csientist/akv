import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../core/appwrite_client.dart';
import 'pin_service.dart';

class SessionManager {
  static final SessionManager instance = SessionManager._internal();
  SessionManager._internal();

  String? _userId;
  String? _userName;
  String? _userEmail;

  // ── Setters ────────────────────────────────────────────────────────────────

  /// Call once after Appwrite login succeeds.
  void setUser(models.User user) {
    _userId    = user.$id;
    _userName  = user.name;
    _userEmail = user.email;
  }

  /// Directly set by ID — use when restoring session from secure storage
  /// without a full Appwrite round-trip.
  void setUserId(String id, {String? name, String? email}) {
    _userId    = id;
    _userName  = name;
    _userEmail = email;
  }

  void clear() {
    _userId    = null;
    _userName  = null;
    _userEmail = null;
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  /// Synchronous — use this everywhere you stamp a DB record.
  /// Throws loudly if called before login — makes misuse impossible to miss.
  String get currentUserId {
    if (_userId == null) {
      throw StateError(
        'SessionManager: currentUserId accessed before login. '
        'Ensure SessionManager.instance.restore() completes before '
        'any data write.',
      );
    }
    return _userId!;
  }

  String get currentUserName  => _userName  ?? 'Unknown';
  String get currentUserEmail => _userEmail ?? '';
  bool   get isLoggedIn       => _userId != null;

  // ── Session Restore ────────────────────────────────────────────────────────

  /// Called on app startup (in AuthGate) to restore the session from
  /// secure storage without asking the user to log in again.
  ///
  /// Returns true if a valid session was found and the user is populated.
  /// Returns false if the session has expired or doesn't exist.
  Future<bool> restore() async {
    final hasSession = await PinService.instance.hasSession();
    if (!hasSession) return false;

    try {
      final account = Account(AppwriteClient.instance.client);
      final user    = await account.get();
      setUser(user);
      return true;
    } on AppwriteException catch (e) {
      // 401 = session expired, user must log in again
      if (e.code == 401) {
        await PinService.instance.clearSession();
        clear();
        return false;
      }
      // Network error — session token still exists, populate with cached ID
      // so the app works offline. The next online restore will refresh it.
      final sessionId = await PinService.instance.getSession();
      if (sessionId != null) {
        setUserId(sessionId); // fallback: use session token as ID placeholder
        return true;
      }
      return false;
    }
  }
}