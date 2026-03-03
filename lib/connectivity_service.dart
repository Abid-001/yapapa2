import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Background FCM handler (top-level, required by firebase_messaging)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.showFromRemote(message);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  /// Set to true while the user is on the Chat tab — suppresses chat popups.
  static bool isInChatScreen = false;

  // Channel IDs
  static const _kChatChannel   = 'yapapa_chat';
  static const _kPresetChannel = 'yapapa_preset';
  static const _kPokeChannel   = 'yapapa_poke';

  static Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _local.initialize(initSettings);

    const presetChannel = AndroidNotificationChannel(
      _kPresetChannel, 'Notifications',
      description: 'Preset notifications from group members',
      importance: Importance.max, playSound: true, enableVibration: true,
    );
    const chatChannel = AndroidNotificationChannel(
      _kChatChannel, 'Chat Messages',
      description: 'New chat messages', importance: Importance.high, playSound: true,
    );
    const pokeChannel = AndroidNotificationChannel(
      _kPokeChannel, 'Pokes',
      description: 'Poke notifications', importance: Importance.high, playSound: true,
    );
    final plugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.createNotificationChannel(presetChannel);
    await plugin?.createNotificationChannel(chatChannel);
    await plugin?.createNotificationChannel(pokeChannel);

    await _fcm.requestPermission(alert: true, badge: true, sound: true, criticalAlert: true);

    // Foreground: suppress chat when user is already reading the chat tab
    FirebaseMessaging.onMessage.listen((msg) {
      final type = msg.data['type'] ?? 'chat';
      if (type == 'chat' && isInChatScreen) return;
      showFromRemote(msg);
    });

    // Background tap — no re-show needed
    FirebaseMessaging.onMessageOpenedApp.listen((_) {});
  }

  static Future<void> showFromRemote(RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title'] ?? 'Yapapa';
    final body  = message.notification?.body  ?? message.data['body']  ?? '';
    final type  = message.data['type'] ?? 'chat';
    await _showLocal(
      title: title, body: body,
      channelId: type == 'preset' ? _kPresetChannel : type == 'poke' ? _kPokeChannel : _kChatChannel,
    );
  }

  static Future<void> _showLocal({
    required String title, required String body,
    String channelId = _kChatChannel, int? id,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == _kPresetChannel ? 'Notifications' : channelId == _kPokeChannel ? 'Pokes' : 'Chat Messages',
      importance: channelId == _kPresetChannel ? Importance.max : Importance.high,
      priority: Priority.high, showWhen: true,
      styleInformation: BigTextStyleInformation(body),
    );
    await _local.show(
      id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
      title, body, NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> showScreentimePoke(String fromName) => _showLocal(
    title: '👆 $fromName poked you!', body: 'Hey, put the phone down!', channelId: _kPokeChannel);

  static Future<void> showScreentimeLimitAlert(int minutes) async {
    final h = minutes ~/ 60; final m = minutes % 60;
    final t = h > 0 ? '${h}h ${m}m' : '${m}m';
    await _showLocal(title: 'Screentime Limit Reached', body: "You've been on your phone for $t!", channelId: _kPokeChannel);
  }

  static Future<void> showPresetMessage(String senderName, String message) =>
    _showLocal(title: '🔔 $senderName', body: message, channelId: _kPresetChannel);

  static Future<void> showChatMessage(String senderName, String message) =>
    _showLocal(title: '💬 $senderName', body: message, channelId: _kChatChannel);

  static Future<String?> getFcmToken() async {
    try { return await _fcm.getToken(); } catch (_) { return null; }
  }
}
