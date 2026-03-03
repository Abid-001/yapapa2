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
      // Cap per-app minutes to the window size — Android sometimes gives full-day stats
      final windowMinutes = end.difference(start).inMinutes.clamp(0, 1440);
      final Map<String, int> result = {};
      for (final info in usage) {
        // Cap each app's time to the window too
        final minutes = info.usage.inMinutes.clamp(0, windowMinutes);
        if (minutes < 1) continue;
        String name = _knownApps[info.packageName] ?? '';
        if (name.isEmpty) name = info.appName;
        if (name.contains('.') && name == name.toLowerCase()) {
          final parts = name.split('.');
          name = parts.last
              .replaceAll('_', ' ')
              .split(' ')
              .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
              .join(' ');
        }
        if (name.isEmpty || name.toLowerCase() == 'android' ||
            name.toLowerCase().contains('launcher')) continue;
        result[name] = (result[name] ?? 0) + minutes;
      }
      // Final safety: cap total to window size
      final total = result.values.fold(0, (a, b) => a + b);
      if (total > windowMinutes) {
        // Scale down proportionally
        final scale = windowMinutes / total;
        return result.map((k, v) => MapEntry(k, (v * scale).round()));
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  // ── Backfill historical screentime on login ───────────────────────────────
  // Reads from Android UsageStats for past days that are missing in Firestore.
  // Android keeps UsageStats for ~30 days, so we can recover data from logged-out period.
  Future<void> backfillHistoricalScreentime({
    required String uid,
    required String groupId,
    int? dailyLimitMinutes,
    int daysBack = 30,
  }) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Get existing record IDs from Firestore for this user (last daysBack days)
      final cutoff = today.subtract(Duration(days: daysBack));
      final existingSnap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('screentime')
          .where('uid', isEqualTo: uid)
          .where('date', isGreaterThanOrEqualTo: cutoff.toIso8601String())
          .get();
      final existingDates = existingSnap.docs
          .map((d) => (d.data()['date'] as String).substring(0, 10))
          .toSet();

      // For each missing day, fetch from Android UsageStats and upload
      for (int i = 1; i <= daysBack; i++) {
        final day = today.subtract(Duration(days: i));
        final dateStr = day.toIso8601String().substring(0, 10);

        // Skip if we already have this day
        if (existingDates.contains(dateStr)) continue;

        final dayEnd = day.add(const Duration(days: 1));
        final appUsage = await getRawAppUsage(day, dayEnd);
        if (appUsage.isEmpty) continue;

        final totalMinutes = appUsage.values.fold(0, (a, b) => a + b);
        if (totalMinutes < 1) continue;

        final id = '${uid}_$dateStr';
        final model = ScreentimeModel(
          id: id,
          uid: uid,
          groupId: groupId,
          date: day,
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

        // Small delay to avoid hammering Firestore
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {}
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
      final rawTotal = appUsage.values.fold(0, (a, b) => a + b);
      // Hard cap: cannot use more time than has elapsed since midnight
      final elapsedMinutes = now.difference(dayStart).inMinutes.clamp(0, 1440);
      final totalMinutes = rawTotal.clamp(0, elapsedMinutes);

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

  // ── Stream own screentime for a date range (realtime) ────────────────────
  Stream<List<ScreentimeModel>> streamMyScreentime({
    required String groupId,
    required String uid,
    required DateTime from,
    required DateTime to,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('screentime')
        .where('uid', isEqualTo: uid)
        .where('date', isGreaterThanOrEqualTo: from.toIso8601String())
        .where('date', isLessThan: to.toIso8601String())
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ScreentimeModel.fromMap(d.data() as Map<String, dynamic>))
            .toList());
  }

  // ── Stream all members' monthly screentime (realtime for leaderboard) ─────
  Stream<Map<String, int>> streamAllMembersMonthlyScreentime({
    required String groupId,
    required List<String> memberUids,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('screentime')
        .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('date', isLessThan: end.toIso8601String())
        .snapshots()
        .map((snap) {
      final Map<String, int> totals = {for (final uid in memberUids) uid: 0};
      for (final doc in snap.docs) {
        final s = ScreentimeModel.fromMap(doc.data() as Map<String, dynamic>);
        if (totals.containsKey(s.uid)) {
          totals[s.uid] = totals[s.uid]! + s.totalMinutes;
        }
      }
      return totals;
    });
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

  // ── Get all members' weekly screentime totals (for leaderboard) ─────────
  Future<Map<String, int>> getAllMembersWeeklyScreentime({
    required String groupId,
    required List<String> memberUids,
    required DateTime weekStart,
  }) async {
    try {
      final end = weekStart.add(const Duration(days: 7));
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('screentime')
          .where('date', isGreaterThanOrEqualTo: weekStart.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      final Map<String, int> totals = {for (final uid in memberUids) uid: 0};
      for (final doc in snap.docs) {
        final s = ScreentimeModel.fromMap(doc.data() as Map<String, dynamic>);
        if (totals.containsKey(s.uid)) totals[s.uid] = totals[s.uid]! + s.totalMinutes;
      }
      return totals;
    } catch (_) { return {}; }
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
