import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';

class PinService {
  static final PinService instance = PinService._internal();
  PinService._internal();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _sessionKey = 'appwrite_session';
  static const _pinSetKey  = 'pin_is_set';

  // ── PIN Hashing ────────────────────────────────────────────────────────────

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  // ── PIN Setup ──────────────────────────────────────────────────────────────

  Future<void> setPin(String pin) async {
    final hash = _hashPin(pin);
    final now = DateTime.now().toIso8601String();
    final db = await LocalDb.instance.database;

    await db.insert(
      'auth_config',
      {'id': 1, 'pin_hash': hash, 'created_at': now, 'last_changed_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _storage.write(key: _pinSetKey, value: 'true');
  }

  Future<bool> verifyPin(String pin) async {
    final hash = _hashPin(pin);
    final db = await LocalDb.instance.database;
    final rows = await db.query('auth_config', where: 'id = 1');
    if (rows.isEmpty) return false;
    return rows.first['pin_hash'] == hash;
  }

  Future<bool> hasPin() async {
    final val = await _storage.read(key: _pinSetKey);
    return val == 'true';
  }

  Future<void> changePin(String oldPin, String newPin) async {
    if (!await verifyPin(oldPin)) throw Exception('Incorrect current PIN');
    await setPin(newPin);
    final db = await LocalDb.instance.database;
    await db.update('auth_config',
        {'last_changed_at': DateTime.now().toIso8601String()}, where: 'id = 1');
  }

  // ── Appwrite Session ───────────────────────────────────────────────────────

  Future<void> saveSession(String sessionId) =>
      _storage.write(key: _sessionKey, value: sessionId);

  Future<String?> getSession() => _storage.read(key: _sessionKey);

  Future<bool> hasSession() async {
    final s = await getSession();
    return s != null && s.isNotEmpty;
  }

  Future<void> clearSession() => _storage.delete(key: _sessionKey);

  Future<void> logout() => _storage.delete(key: _sessionKey);

  Future<void> fullReset() async {
    await _storage.deleteAll();
    final db = await LocalDb.instance.database;
    await db.delete('auth_config');
  }
}