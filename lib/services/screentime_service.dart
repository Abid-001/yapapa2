import 'package:app_usage/app_usage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/screentime_model.dart';
import 'notification_service.dart';

class ScreentimeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Known package name → friendly name map ──────────────────────────────────
  static const _knownApps = {
    'com.whatsapp': 'WhatsApp',
    'com.facebook.katana': 'Facebook',
    'com.instagram.android': 'Instagram',
    'com.twitter.android': 'Twitter / X',
    'com.google.android.youtube': 'YouTube',
    'com.google.android.gm': 'Gmail',
    'com.google.android.apps.maps': 'Google Maps',
    'com.google.android.googlequicksearchbox': 'Google Search',
    'com.google.android.apps.photos': 'Google Photos',
    'com.google.android.apps.messaging': 'Messages',
    'com.google.android.dialer': 'Phone',
    'com.android.chrome': 'Chrome',
    'org.telegram.messenger': 'Telegram',
    'com.snapchat.android': 'Snapchat',
    'com.tiktok': 'TikTok',
    'com.zhiliaoapp.musically': 'TikTok',
    'com.spotify.music': 'Spotify',
    'com.netflix.mediaclient': 'Netflix',
    'com.google.android.apps.youtube.music': 'YouTube Music',
    'com.google.android.apps.tachyon': 'Google Meet',
    'com.microsoft.teams': 'Microsoft Teams',
    'com.discord': 'Discord',
    'com.linkedin.android': 'LinkedIn',
    'com.amazon.mShop.android.shopping': 'Amazon',
    'com.android.settings': 'Settings',
    'com.android.launcher': 'Launcher',
    'com.samsung.android.app.notes': 'Samsung Notes',
    'com.samsung.android.messaging': 'Messages',
    'com.samsung.android.contacts': 'Contacts',
    'com.google.android.contacts': 'Contacts',
    'com.google.android.calendar': 'Google Calendar',
    'com.google.android.keep': 'Google Keep',
    'com.microsoft.office.word': 'Microsoft Word',
    'com.microsoft.office.excel': 'Microsoft Excel',
    'com.bykvik.yapapa': 'Yapapa',
    'com.yapapa.app': 'Yapapa',
  };

  // ── Fetch raw usage from Android UsageStats ────────────────────────────────
  Future<Map<String, int>> getRawAppUsage(DateTime start, DateTime end) async {
    try {
      final usage = await AppUsage().getAppUsage(start, end);
      final Map<String, int> result = {};
      for (final info in usage) {
        final minutes = info.usage.inMinutes;
        if (minutes < 1) continue;
        // Try known map first
        String name = _knownApps[info.packageName] ?? '';
        // If not known, use appName from the package (may already be clean)
        if (name.isEmpty) {
          name = info.appName;
        }
        // If still looks like a package name (contains dots, lowercase), clean it up
        if (name.contains('.') && name == name.toLowerCase()) {
          // Extract last segment and capitalize
          final parts = name.split('.');
          name = parts.last
              .replaceAll('_', ' ')
              .split(' ')
              .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
              .join(' ');
        }
        // Skip system junk
        if (name.isEmpty || name.toLowerCase() == 'android' ||
            name.toLowerCase().contains('launcher')) continue;
        // Merge duplicates (same friendly name)
        result[name] = (result[name] ?? 0) + minutes;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  // ── Upload today's screentime to Firestore ─────────────────────────────────
  Future<void> syncTodayScreentime({
    required String uid,
    required String groupId,
    required int? dailyLimitMinutes,
  }) async {
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final appUsage = await getRawAppUsage(dayStart, now);
      final totalMinutes = appUsage.values.fold(0, (a, b) => a + b);

      final id = '${uid}_${dayStart.toIso8601String().substring(0, 10)}';
      final model = ScreentimeModel(
        id: id,
        uid: uid,
        groupId: groupId,
        date: dayStart,
        totalMinutes: totalMinutes,
        appUsage: appUsage,
        dailyLimitMinutes: dailyLimitMinutes,
      );

      await _db
          .collection('groups')
          .doc(groupId)
          .collection('screentime')
          .doc(id)
          .set(model.toMap());

      // Check if over limit and notify
      if (dailyLimitMinutes != null && totalMinutes > dailyLimitMinutes) {
        final prefs = await SharedPreferences.getInstance();
        final notifiedKey = 'limit_notified_${dayStart.toIso8601String().substring(0, 10)}';
        final alreadyNotified = prefs.getBool(notifiedKey) ?? false;
        if (!alreadyNotified) {
          await NotificationService.showScreentimeLimitAlert(totalMinutes);
          await prefs.setBool(notifiedKey, true);
        }
      }
    } catch (_) {}
  }

  // ── Get own screentime for a date range ───────────────────────────────────
  Future<List<ScreentimeModel>> getMyScreentime({
    required String groupId,
    required String uid,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('screentime')
          .where('uid', isEqualTo: uid)
          .where('date', isGreaterThanOrEqualTo: from.toIso8601String())
          .where('date', isLessThan: to.toIso8601String())
          .orderBy('date', descending: true)
          .get();
      return snap.docs
          .map((d) => ScreentimeModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Get all members' monthly total screentime (for leaderboard) ────────────
  Future<Map<String, int>> getAllMembersMonthlyScreentime({
    required String groupId,
    required List<String> memberUids,
    required DateTime month,
  }) async {
    try {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('screentime')
          .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();

      final Map<String, int> totals = {
        for (final uid in memberUids) uid: 0,
      };
      for (final doc in snap.docs) {
        final s = ScreentimeModel.fromMap(doc.data() as Map<String, dynamic>);
        if (totals.containsKey(s.uid)) {
          totals[s.uid] = totals[s.uid]! + s.totalMinutes;
        }
      }
      return totals;
    } catch (_) {
      return {};
    }
  }

  // ── Save/get daily limit preference ───────────────────────────────────────
  Future<void> saveDailyLimit(int minutes, {String? uid}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_limit_minutes', minutes);
    // Also write to Firestore so friends can check for poke
    if (uid != null) {
      try {
        await _db.collection('userLimits').doc(uid).set({
          'limitMinutes': minutes,
          'uid': uid,
        });
      } catch (_) {}
    }
  }

  Future<int> getDailyLimit({int groupDefault = 180}) async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt('daily_limit_minutes');
    return val ?? groupDefault;
  }

  // ── Cleanup old screentime data (2 months) ─────────────────────────────────
  Future<void> cleanupOldScreentime(String groupId) async {
    try {
      final twoMonthsAgo = DateTime.now().subtract(const Duration(days: 60));
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('screentime')
          .where('date', isLessThan: twoMonthsAgo.toIso8601String())
          .limit(50)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      if (snap.docs.isNotEmpty) await batch.commit();
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static int totalMinutesFromList(List<ScreentimeModel> list) =>
      list.fold(0, (sum, s) => sum + s.totalMinutes);

  static String formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  static DateTime get todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime get weekStart {
    final now = DateTime.now();
    // Week runs Sat→Fri. Saturday = weekday 6
    int daysSinceSat = (now.weekday + 1) % 7; // 0 on Sat, 1 on Sun, ..., 6 on Fri
    final sat = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysSinceSat));
    return sat;
  }

  static DateTime get weekEnd {
    return weekStart.add(const Duration(days: 7));
  }

  static DateTime get monthStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  static DateTime get monthEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 1);
  }
}
