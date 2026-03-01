import 'package:app_usage/app_usage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/screentime_model.dart';
import 'notification_service.dart';

class ScreentimeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Fetch raw usage from Android UsageStats ────────────────────────────────
  Future<Map<String, int>> getRawAppUsage(DateTime start, DateTime end) async {
    try {
      final usage = await AppUsage().getAppUsage(start, end);
      final Map<String, int> result = {};
      for (final info in usage) {
        final minutes = info.usage.inMinutes;
        if (minutes > 0) {
          result[info.appName] = minutes;
        }
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
          .map((d) => ScreentimeModel.fromMap(d.data()))
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
        final s = ScreentimeModel.fromMap(doc.data());
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
  Future<void> saveDailyLimit(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_limit_minutes', minutes);
  }

  Future<int?> getDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt('daily_limit_minutes');
    return val;
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
    return now.subtract(Duration(days: now.weekday - 1));
  }

  static DateTime get monthStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }
}
