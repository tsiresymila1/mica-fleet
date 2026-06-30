import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../features/delais/domain/delai_alert_planner.dart';

/// Livraison des rappels de délai via notifications locales (offline).
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const _channelId = 'delais';

  /// [onTap] reçoit le payload (ex. id de chargement) quand l'utilisateur
  /// tape une notification → permet d'ouvrir l'écran correspondant.
  Future<void> init({void Function(String payload)? onTap}) async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Indian/Antananarivo')); // Madagascar
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && p.isNotEmpty) onTap?.call(p);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Programme les rappels futurs (ignore ceux déjà passés).
  /// [payload] est transmis au tap (ex. id de chargement).
  Future<void> scheduleRappels(int baseId, List<RappelDelai> rappels,
      {String? payload}) async {
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
        payload: payload,
      );
    }
  }
}
