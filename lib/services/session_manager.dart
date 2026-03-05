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
      // Network error — restore from the cached user ID we saved at last login.
      // This guarantees created_by stamps match the real Appwrite user ID even
      // while offline, so records reconcile correctly once connectivity returns.
      final cachedId   = await PinService.instance.getCachedUserId();
      final cachedName = await PinService.instance.getCachedUserName();
      if (cachedId != null) {
        setUserId(cachedId, name: cachedName);
        return true;
      }
      // No cached ID means the user has never successfully logged in on this
      // device while online — force a fresh login to populate it.
      return false;
    }
  }
}