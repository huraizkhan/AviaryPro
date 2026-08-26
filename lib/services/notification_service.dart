import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../database/database_helper.dart';

@pragma('vm:entry-point')
void hatchNotificationDismissedBackground(
  NotificationResponse response,
) async {
  if (response.notificationResponseType !=
          NotificationResponseType.notificationDismissed ||
      response.payload == null) {
    return;
  }
  await NotificationService.instance.reshowDismissedSilently(response.payload!);
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int _hatchStatusId = 74001;
  static const String _alertedSignatureKey = 'hatch_status_alerted_signature_v2';
  static const String _scheduledSignatureKey = 'hatch_status_scheduled_signature_v2';
  static const String _migrationKey = 'hatch_status_notification_v2_migrated';
  static const String _contentSignatureKey = 'hatch_status_content_signature_v2';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      final timezone = await FlutterTimezone.getLocalTimezone();
      try {
        tz.setLocalLocation(tz.getLocation(timezone.identifier));
      } on Object {
        tz.setLocalLocation(tz.UTC);
      }

      const android = AndroidInitializationSettings('ic_stat_aviary');
      const darwin = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveBackgroundNotificationResponse:
            hatchNotificationDismissedBackground,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _initialized = true;
    } on Object catch (error, stackTrace) {
      debugPrint('Notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  NotificationDetails _details({
    required bool audible,
    required int timeoutMs,
    required String body,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        audible ? 'aviary_hatch_alerts_v2' : 'aviary_hatch_status_silent_v2',
        audible ? 'Hatch alerts' : 'Hatch status',
        channelDescription: audible
            ? 'First hatch and overdue alert of the day'
            : 'Silent persistent hatch and overdue status',
        importance: audible ? Importance.high : Importance.low,
        priority: audible ? Priority.high : Priority.low,
        playSound: audible,
        enableVibration: audible,
        silent: !audible,
        icon: 'ic_stat_aviary',
        autoCancel: false,
        ongoing: false,
        onlyAlertOnce: !audible,
        timeoutAfter: timeoutMs,
        dismissIsolate: NotificationDismissedIsolate.background,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: audible,
        presentSound: audible,
      ),
    );
  }

  String _dateKey(tz.TZDateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  String _body(Map<String, dynamic> summary) {
    final lines = <String>[];
    final overdueRaw = summary['overdueByDays'];
    if (overdueRaw is Map) {
      final groups = <MapEntry<int, int>>[];
      for (final entry in overdueRaw.entries) {
        final days =
            entry.key is int ? entry.key as int : int.tryParse('${entry.key}');
        final count = entry.value is int
            ? entry.value as int
            : int.tryParse('${entry.value}');
        if (days != null && count != null && count > 0) {
          groups.add(MapEntry(days, count));
        }
      }
      groups.sort((a, b) => b.key.compareTo(a.key));
      for (final group in groups) {
        lines.add(
          '${group.value} egg${group.value == 1 ? '' : 's'} • '
          '${group.key} day${group.key == 1 ? '' : 's'} overdue',
        );
      }
    }
    final today = (summary['dueToday'] as num?)?.toInt() ?? 0;
    if (today > 0) {
      lines.add('$today egg${today == 1 ? '' : 's'} • Should hatch today');
    }
    return lines.join('\n');
  }

  String _payload({
    required String title,
    required String body,
    required DateTime expiresAt,
  }) {
    return jsonEncode({
      'kind': 'hatch_status',
      'title': title,
      'body': body,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    });
  }

  Future<void> reshowDismissedSilently(String payload) async {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded['kind'] != 'hatch_status') return;
      final now = DateTime.now();
      // Never restore the hatch status during the midnight-to-07:59 quiet window.
      if (now.hour < 8) return;
      final expiresMs = decoded['expiresAt'] is int
          ? decoded['expiresAt'] as int
          : int.tryParse('${decoded['expiresAt']}');
      if (expiresMs == null) return;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresMs);
      if (!expiresAt.isAfter(now)) return;
      final title = decoded['title']?.toString() ?? '';
      final body = decoded['body']?.toString() ?? '';
      if (title.isEmpty || body.isEmpty) return;

      const android = AndroidInitializationSettings('ic_stat_aviary');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(
        settings: settings,
        onDidReceiveBackgroundNotificationResponse:
            hatchNotificationDismissedBackground,
      );
      await _plugin.show(
        id: _hatchStatusId,
        title: title,
        body: body,
        notificationDetails: _details(
          audible: false,
          timeoutMs: expiresAt.difference(now).inMilliseconds,
          body: body,
        ),
        payload: payload,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('Could not silently restore hatch notification: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> syncFromDatabase() async {
    await initialize();
    if (!_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_migrationKey) ?? false)) {
        // Clear the older per-egg/per-pair scheduled notifications once.
        await _plugin.cancelAll();
        await prefs.setBool(_migrationKey, true);
      }

      final summary =
          await DatabaseHelper.instance.getHatchNotificationSummary();
      final total = (summary['total'] as num?)?.toInt() ?? 0;
      final now = tz.TZDateTime.now(tz.local);
      final signature = _dateKey(now);
      final title = '$total egg${total == 1 ? '' : 's'} need attention';
      final body = _body(summary);

      // Quiet window: no hatch notification at all from midnight through 07:59.
      if (now.hour < 8) {
        await _plugin.cancel(id: _hatchStatusId);
        if (total > 0) {
          final atEight =
              tz.TZDateTime(tz.local, now.year, now.month, now.day, 8);
          final previousAlerted = prefs.getString(_alertedSignatureKey);
          final audible = previousAlerted != signature;
          final midnight = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day + 1,
          );
          final timeoutMs = midnight.difference(atEight).inMilliseconds;
          final payload = _payload(
            title: title,
            body: body,
            expiresAt: midnight,
          );
          await _plugin.zonedSchedule(
            id: _hatchStatusId,
            title: title,
            body: body,
            scheduledDate: atEight,
            notificationDetails: _details(
              audible: audible,
              timeoutMs: timeoutMs,
              body: body,
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: payload,
          );
          // Remember that today's first alert has already been scheduled. This
          // prevents a second popup/sound if the app is opened after 08:00.
          await prefs.setString(_scheduledSignatureKey, signature);
          await prefs.setString(_contentSignatureKey, '$signature|$title|$body');
        } else {
          await prefs.remove(_scheduledSignatureKey);
          await prefs.remove(_contentSignatureKey);
        }
        return;
      }

      if (total == 0) {
        await _plugin.cancel(id: _hatchStatusId);
        await prefs.remove(_scheduledSignatureKey);
        await prefs.remove(_contentSignatureKey);
        return;
      }

      final previousAlerted = prefs.getString(_alertedSignatureKey);
      final previousScheduled = prefs.getString(_scheduledSignatureKey);
      final contentSignature = '$signature|$title|$body';
      final previousContent = prefs.getString(_contentSignatureKey);

      // Opening/resuming the app must not repost the same notification. Reposting
      // the same ID can still create a heads-up banner on some Android skins.
      if (previousContent == contentSignature &&
          (previousAlerted == signature || previousScheduled == signature)) {
        if (previousScheduled == signature) {
          await prefs.setString(_alertedSignatureKey, signature);
          await prefs.remove(_scheduledSignatureKey);
        }
        return;
      }

      final audible =
          previousAlerted != signature && previousScheduled != signature;
      final midnight = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
      );
      final timeoutMs = midnight.difference(now).inMilliseconds;
      final payload = _payload(
        title: title,
        body: body,
        expiresAt: midnight,
      );

      await _plugin.show(
        id: _hatchStatusId,
        title: title,
        body: body,
        notificationDetails: _details(
          audible: audible,
          timeoutMs: timeoutMs,
          body: body,
        ),
        payload: payload,
      );
      // Either this call produced the first alert, or the scheduled 08:00 alert
      // already did. In both cases every later refresh today must be silent.
      await prefs.setString(_alertedSignatureKey, signature);
      await prefs.setString(_contentSignatureKey, contentSignature);
      await prefs.remove(_scheduledSignatureKey);
    } on Object catch (error, stackTrace) {
      debugPrint('Notification sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
