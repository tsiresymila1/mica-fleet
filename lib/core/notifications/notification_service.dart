import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../features/delais/domain/delai_alert_planner.dart';

/// Livraison des rappels de délai via notifications locales (offline).
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const _channelId = 'delais';

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Indian/Antananarivo')); // Madagascar
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
        settings: const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Programme les rappels futurs (ignore ceux déjà passés).
  Future<void> scheduleRappels(int baseId, List<RappelDelai> rappels) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Rappels de délai',
        channelDescription: 'Alerte avant et à échéance de livraison',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    final now = DateTime.now();
    for (var i = 0; i < rappels.length; i++) {
      final r = rappels[i];
      if (r.quand.isBefore(now)) continue;
      await _plugin.zonedSchedule(
        id: baseId + i,
        title: 'Mica — rappel',
        body: r.message,
        scheduledDate: tz.TZDateTime.from(r.quand, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
