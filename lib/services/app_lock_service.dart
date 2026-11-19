import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockService extends ChangeNotifier {
  AppLockService._();
  static final instance = AppLockService._();

  static const _enabledKey = 'local_app_lock_enabled';
  static const _saltKey = 'local_app_lock_salt';
  static const _hashKey = 'local_app_lock_hash';
  bool _enabled = false;
  bool _locked = false;

  bool get isEnabled => _enabled;
  bool get isLocked => _locked;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_enabledKey) ?? false;
    _locked = _enabled;
  }

  Future<void> enable(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('Use a six-digit PIN.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_saltKey, base64Encode(salt));
    await preferences.setString(_hashKey, await _derive(pin, salt));
    await preferences.setBool(_enabledKey, true);
    _enabled = true;
    _locked = false;
    notifyListeners();
  }

  Future<bool> verify(String pin) async {
    final preferences = await SharedPreferences.getInstance();
    final encodedSalt = preferences.getString(_saltKey);
    final expected = preferences.getString(_hashKey);
    if (encodedSalt == null || expected == null) return false;
    final actual = await _derive(pin, base64Decode(encodedSalt));
    if (!_constantTimeEquals(actual, expected)) return false;
    _locked = false;
    notifyListeners();
    return true;
  }

  Future<bool> disable(String pin) async {
    if (!await verify(pin)) return false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_saltKey);
    await preferences.remove(_hashKey);
    await preferences.setBool(_enabledKey, false);
    _enabled = false;
    _locked = false;
    notifyListeners();
    return true;
  }

  void lock() {
    if (!_enabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  Future<String> _derive(String pin, List<int> salt) =>
      compute(_derivePinHash, {
        'pin': pin,
        'salt': salt,
      });

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}

String _derivePinHash(Map<String, dynamic> input) {
  final key = utf8.encode(input['pin'] as String);
  final salt = List<int>.from(input['salt'] as List);
  final hmac = Hmac(sha256, key);
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var round = 1; round < 100000; round++) {
    block = hmac.convert(block).bytes;
    for (var index = 0; index < result.length; index++) {
      result[index] ^= block[index];
    }
  }
  return base64Encode(result);
}
