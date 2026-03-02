import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _local.initialize(initSettings);
    await _fcm.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(
        title: message.notification?.title ?? 'Yapapa',
        body: message.notification?.body ?? '',
      );
    });
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    int? id,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'yapapa_channel', 'Yapapa Notifications',
      channelDescription: 'Notifications from Yapapa',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _local.show(
      id ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      title, body, details,
    );
  }

  // Poke: shows sender name
  static Future<void> showScreentimePoke(String fromName) async {
    await _showLocalNotification(
      title: '👆 $fromName poked you!',
      body: 'Hey, put the phone down!',
    );
  }

  static Future<void> showScreentimeLimitAlert(int minutes) async {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';
    await _showLocalNotification(
      title: '📱 Screentime Limit Reached',
      body: "You've been on your phone for $timeStr. Your friends were notified!",
    );
  }

  // Preset notification: shows sender name in title
  static Future<void> showPresetMessage(String senderName, String message) async {
    await _showLocalNotification(
      title: '🔔 $senderName sent a notification',
      body: message,
    );
  }

  // Chat message: shows sender name
  static Future<void> showChatMessage(String senderName, String message) async {
    await _showLocalNotification(
      title: '💬 $senderName',
      body: message,
    );
  }

  static Future<String?> getFcmToken() async {
    try { return await _fcm.getToken(); } catch (_) { return null; }
  }
}
