import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudyPreferencesService {
  static const _outputKey = 'settings_default_output_format';
  static const _reminderEnabledKey = 'settings_study_reminder_enabled';
  static const _reminderHourKey = 'settings_study_reminder_hour';
  static const _reminderMinuteKey = 'settings_study_reminder_minute';
  static const _reminderChannel = MethodChannel('convert2file/study_reminder');

  static const supportedOutputFormats = ['docx', 'pdf', 'html', 'txt'];

  Future<String> defaultOutputFormat() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_outputKey);
    return supportedOutputFormats.contains(saved) ? saved! : 'docx';
  }

  Future<void> setDefaultOutputFormat(String format) async {
    if (!supportedOutputFormats.contains(format)) {
      throw ArgumentError.value(format, 'format', 'Unsupported output format');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_outputKey, format);
  }

  Future<bool> reminderEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_reminderEnabledKey) ?? false;
  }

  Future<({int hour, int minute})> reminderTime() async {
    final preferences = await SharedPreferences.getInstance();
    return (
      hour: preferences.getInt(_reminderHourKey) ?? 19,
      minute: preferences.getInt(_reminderMinuteKey) ?? 0,
    );
  }

  Future<void> setReminderTime(int hour, int minute) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_reminderHourKey, hour);
    await preferences.setInt(_reminderMinuteKey, minute);
    if (preferences.getBool(_reminderEnabledKey) == true) {
      await _reminderChannel.invokeMethod<void>('schedule', {
        'hour': hour,
        'minute': minute,
      });
    }
  }

  Future<bool> setReminderEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    if (enabled) {
      final granted =
          await _reminderChannel.invokeMethod<bool>('requestPermission') ??
              false;
      if (!granted) return false;
      final time = await reminderTime();
      await _reminderChannel.invokeMethod<void>('schedule', {
        'hour': time.hour,
        'minute': time.minute,
      });
    } else {
      await _reminderChannel.invokeMethod<void>('cancel');
    }
    await preferences.setBool(_reminderEnabledKey, enabled);
    return true;
  }
}
