import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class AppNotifications {
  AppNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'ak_edu_reminders',
    'AK Edu Point reminders',
    description: 'Attendance, fee and weekly tuition reminders',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    tzdata.initializeTimeZones();
    // AK Edu Point is configured for India-based tuition use.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.requestNotificationsPermission();
  }

  static NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          'ak_edu_reminders',
          'AK Edu Point reminders',
          channelDescription: 'Attendance, fee and weekly tuition reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      );

  static tz.TZDateTime _nextTime(int hour, int minute, {int? weekday}) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (weekday != null) {
      while (next.weekday != weekday || !next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }
    } else if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  static Future<void> _scheduleDaily(
      int id, String title, String body, int hour, int minute) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextTime(hour, minute),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> setAttendanceReminder(bool enabled) async {
    if (enabled) {
      await _scheduleDaily(201, 'Attendance reminder',
          'Aaj ki tuition attendance mark karna na bhoolein.', 8, 0);
    } else {
      await _plugin.cancel(201);
    }
  }

  static Future<void> setFeeReminder(bool enabled) async {
    if (enabled) {
      await _scheduleDaily(202, 'Fee follow-up reminder',
          'Pending fees check karein aur zaroori reminders bhejein.', 9, 0);
    } else {
      await _plugin.cancel(202);
    }
  }

  static Future<void> setWeeklySummary(bool enabled) async {
    if (enabled) {
      await _plugin.zonedSchedule(
        203,
        'Weekly tuition review',
        'Is hafte ki attendance, fees aur student progress review karein.',
        _nextTime(19, 0, weekday: DateTime.sunday),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } else {
      await _plugin.cancel(203);
    }
  }
}
