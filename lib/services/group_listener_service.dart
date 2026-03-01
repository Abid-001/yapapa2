import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

/// This service runs in the background after login.
/// It listens for:
///   1. Pokes sent to the current user
///   2. Preset notifications sent by any group member
/// When detected, it fires a local push notification immediately.
class GroupListenerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot>? _pokeStream;
  Stream<QuerySnapshot>? _notifStream;

  void startListening({
    required String uid,
    required String groupId,
    required String username,
  }) {
    _listenForPokes(uid: uid, groupId: groupId);
    _listenForPresetNotifications(
        groupId: groupId, currentUid: uid, currentUsername: username);
  }

  // ── Poke Listener ──────────────────────────────────────────────────────────
  void _listenForPokes({
    required String uid,
    required String groupId,
  }) {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 10000;

    _pokeStream = _db
        .collection('groups')
        .doc(groupId)
        .collection('pokes')
        .where('targetUid', isEqualTo: uid)
        .where('timestamp', isGreaterThan: cutoff)
        .snapshots();

    _pokeStream!.listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final rawData = change.doc.data();
          if (rawData == null) continue;
          // Cast to Map so we can use [] operator safely
          final data = rawData as Map<String, dynamic>;

          final pokeKey = 'poke_seen_${change.doc.id}';
          final prefs = await SharedPreferences.getInstance();
          final alreadySeen = prefs.getBool(pokeKey) ?? false;

          if (!alreadySeen) {
            await NotificationService.showScreentimePoke('Your friend');
            await prefs.setBool(pokeKey, true);

            // Auto-clean poke after firing so it doesn't repeat
            try {
              await change.doc.reference.delete();
            } catch (_) {}
          }
        }
      }
    });
  }

  // ── Preset Notification Listener ───────────────────────────────────────────
  void _listenForPresetNotifications({
    required String groupId,
    required String currentUid,
    required String currentUsername,
  }) {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 10000;

    _notifStream = _db
        .collection('groups')
        .doc(groupId)
        .collection('notifications')
        .where('timestamp', isGreaterThan: cutoff)
        .snapshots();

    _notifStream!.listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final rawData = change.doc.data();
          if (rawData == null) continue;
          // Cast to Map so we can use [] operator safely
          final data = rawData as Map<String, dynamic>;

          final notifKey = 'notif_seen_${change.doc.id}';
          final prefs = await SharedPreferences.getInstance();
          final alreadySeen = prefs.getBool(notifKey) ?? false;

          if (!alreadySeen) {
            final senderName = data['senderName'] as String? ?? 'Someone';
            final text = data['text'] as String? ?? '';

            if (senderName != currentUsername) {
              await NotificationService.showPresetMessage(senderName, text);
            }

            await prefs.setBool(notifKey, true);

            // Clean up old notification docs
            try {
              final ts = data['timestamp'] as int? ?? 0;
              final age = DateTime.now().millisecondsSinceEpoch - ts;
              if (age > 60000) {
                await change.doc.reference.delete();
              }
            } catch (_) {}
          }
        }
      }
    });
  }

  void stopListening() {
    _pokeStream = null;
    _notifStream = null;
  }
}
