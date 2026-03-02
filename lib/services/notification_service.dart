import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    // Local notifications setup
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _local.initialize(initSettings);

    // FCM permissions
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle foreground FCM messages
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
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'yapapa_channel',
      'Yapapa Notifications',
      channelDescription: 'Notifications from Yapapa',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  static Future<void> showScreentimePoke(String fromUser) async {
    await _showLocalNotification(
      title: '👆 Poke from $fromUser!',
      body: 'Hey, put the phone down!',
    );
  }

  static Future<void> showScreentimeLimitAlert(int minutes) async {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';
    await _showLocalNotification(
      title: '📱 Screentime Limit Reached',
      body: 'You\'ve been on your phone for $timeStr. Your friends were notified!',
    );
  }

  static Future<void> showPresetMessage(
      String senderName, String message) async {
    await _showLocalNotification(
      title: '🔔 \$senderName',
      body: message,
    );
  }

  static Future<void> showChatMessage(
      String senderName, String message) async {
    await _showLocalNotification(
      title: '💬 \$senderName',
      body: message,
    );
  }

  static Future<String?> getFcmToken() async {
    try {
      return await _fcm.getToken();
    } catch (_) {
      return null;
    }
  }
}
