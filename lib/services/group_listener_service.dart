import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class GroupListenerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription? _pokeSub;
  StreamSubscription? _notifSub;
  StreamSubscription? _chatSub;

  String? _currentUid;
  String? _currentGroupId;
  String? _currentUsername;

  void startListening({
    required String uid,
    required String groupId,
    required String username,
  }) {
    _currentUid = uid;
    _currentGroupId = groupId;
    _currentUsername = username;
    _listenForPokes(uid: uid, groupId: groupId);
    _listenForPresetNotifications(groupId: groupId, currentUid: uid, currentUsername: username);
    _listenForChatMessages(groupId: groupId, currentUid: uid);
  }

  // ── Poke Listener ────────────────────────────────────────────────────────────
  void _listenForPokes({required String uid, required String groupId}) {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 10000;
    _pokeSub?.cancel();
    _pokeSub = _db
        .collection('groups')
        .doc(groupId)
        .collection('pokes')
        .where('targetUid', isEqualTo: uid)
        .where('timestamp', isGreaterThan: cutoff)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;
          final pokeKey = 'poke_seen_${change.doc.id}';
          final prefs = await SharedPreferences.getInstance();
          if (!(prefs.getBool(pokeKey) ?? false)) {
            // fromName field must be set by the poke sender
            final fromName = data['fromName'] as String?
                ?? data['senderName'] as String?
                ?? 'Someone';
            await NotificationService.showScreentimePoke(fromName);
            await prefs.setBool(pokeKey, true);
            // Save poke to inbox too
            final inbox = prefs.getStringList('inbox_notifications') ?? [];
            inbox.add(jsonEncode({
              'senderName': fromName,
              'text': '👆 poked you! Put the phone down!',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'isPoke': true,
            }));
            if (inbox.length > 50) inbox.removeAt(0);
            await prefs.setStringList('inbox_notifications', inbox);
            try { await change.doc.reference.delete(); } catch (_) {}
          }
        }
      }
    });
  }

  // ── Preset Notification Listener ─────────────────────────────────────────────
  void _listenForPresetNotifications({
    required String groupId,
    required String currentUid,
    required String currentUsername,
  }) {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 10000;
    _notifSub?.cancel();
    _notifSub = _db
        .collection('groups')
        .doc(groupId)
        .collection('notifications')
        .where('timestamp', isGreaterThan: cutoff)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final notifKey = 'notif_seen_${change.doc.id}';
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(notifKey) ?? false) continue;
        await prefs.setBool(notifKey, true);

        final senderUid = data['senderUid'] as String? ?? '';
        final senderName = data['senderName'] as String? ?? 'Someone';
        final text = data['text'] as String? ?? '';

        // Fix (3): skip if sender is current user — no self-notification
        if (senderUid == currentUid || senderName == currentUsername) continue;

        await NotificationService.showPresetMessage(senderName, text);

        // Save to inbox
        final inbox = prefs.getStringList('inbox_notifications') ?? [];
        inbox.add(jsonEncode({
          'senderName': senderName,
          'text': text,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
        if (inbox.length > 50) inbox.removeAt(0);
        await prefs.setStringList('inbox_notifications', inbox);

        try {
          final ts = data['timestamp'] as int? ?? 0;
          if (DateTime.now().millisecondsSinceEpoch - ts > 60000) {
            await change.doc.reference.delete();
          }
        } catch (_) {}
      }
    });
  }

  // ── Chat Message Listener ─────────────────────────────────────────────────────
  void _listenForChatMessages({
    required String groupId,
    required String currentUid,
  }) {
    _chatSub?.cancel();
    final cutoff = DateTime.now().millisecondsSinceEpoch - 10000;
    _chatSub = FirebaseDatabase.instance
        .ref('chats/$groupId/messages')
        .orderByChild('timestamp')
        .startAt(cutoff)
        .onChildAdded
        .listen((event) async {
      final raw = event.snapshot.value;
      if (raw == null) return;
      final data = Map<String, dynamic>.from(raw as Map);

      final senderUid = data['senderUid'] as String? ?? '';
      // Fix (3): don't notify sender for their own messages
      if (senderUid == currentUid || senderUid == 'system') return;

      final senderName = data['senderName'] as String? ?? 'Someone';
      final text = data['text'] as String? ?? '';
      final isPreset = data['isPreset'] as bool? ?? false;

      // Fix (3): for preset messages, the notification was already sent via
      // the notifications collection listener — skip duplicate here
      if (isPreset) return;

      final msgKey = 'chat_notif_${event.snapshot.key}';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(msgKey) ?? false) return;
      await prefs.setBool(msgKey, true);

      await NotificationService.showChatMessage(senderName, text);
    });
  }

  void stopListening() {
    _pokeSub?.cancel();
    _notifSub?.cancel();
    _chatSub?.cancel();
    _pokeSub = null;
    _notifSub = null;
    _chatSub = null;
  }
}
