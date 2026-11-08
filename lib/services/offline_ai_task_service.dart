import 'dart:io';

import 'package:flutter/services.dart';

class OfflineAiTaskService {
  OfflineAiTaskService._();

  static const MethodChannel _channel =
      MethodChannel('convert2file/offline_ai_task');
  static bool _active = false;

  static Future<void> start({required String title}) async {
    if (!Platform.isAndroid || _active) return;
    await _channel.invokeMethod<bool>('requestNotificationPermission');
    await _channel.invokeMethod<void>('start', {'title': title});
    _active = true;
  }

  static Future<void> updateStatus(String status) async {
    if (!Platform.isAndroid || !_active) return;
    await _channel.invokeMethod<void>('updateStatus', {'status': status});
  }

  static Future<void> finish({
    required bool success,
    required String message,
  }) async {
    if (!Platform.isAndroid || !_active) return;
    _active = false;
    await _channel.invokeMethod<void>('finish', {
      'success': success,
      'message': message,
    });
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid || !_active) return;
    _active = false;
    await _channel.invokeMethod<void>('cancel');
  }
}
