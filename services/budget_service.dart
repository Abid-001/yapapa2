import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense_model.dart';

class BudgetService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Add Expense ────────────────────────────────────────────────────────────
  Future<String?> addExpense(ExpenseModel expense) async {
    try {
      final docRef = _db
          .collection('groups')
          .doc(expense.groupId)
          .collection('expenses')
          .doc();
      final withId = ExpenseModel(
        id: docRef.id,
        uid: expense.uid,
        groupId: expense.groupId,
        amount: expense.amount,
        categoryName: expense.categoryName,
        categoryType: expense.categoryType,
        note: expense.note,
        date: expense.date,
        createdAt: expense.createdAt,
      );
      await docRef.set(withId.toMap());
      return null;
    } catch (e) {
      return 'Failed to save expense. Please try again.';
    }
  }

  // ── Delete Expense ─────────────────────────────────────────────────────────
  Future<void> deleteExpense(
      String groupId, String expenseId) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .doc(expenseId)
          .delete();
    } catch (_) {}
  }

  // ── Update Expense ────────────────────────────────────────────────────────
  Future<String?> updateExpense(ExpenseModel expense) async {
    try {
      await _db
          .collection('groups')
          .doc(expense.groupId)
          .collection('expenses')
          .doc(expense.id)
          .update(expense.toMap());
      return null;
    } catch (e) {
      return 'Failed to update expense. Please try again.';
    }
  }

  // ── Get own expenses for TODAY ─────────────────────────────────────────────
  Stream<List<ExpenseModel>> getMyDailyExpenses({
    required String groupId,
    required String uid,
    required DateTime day,
  }) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .where('uid', isEqualTo: uid)
        .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('date', isLessThan: end.toIso8601String())
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ExpenseModel.fromMap(d.data() as Map<String, dynamic>))
            .toList());
  }

  // ── Get all members' daily totals (for leaderboard today) ─────────────────
  Future<Map<String, double>> getAllMembersDailyTotal({
    required String groupId,
    required List<String> memberUids,
    required DateTime day,
  }) async {
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      final Map<String, double> totals = {for (final uid in memberUids) uid: 0};
      for (final doc in snap.docs) {
        final e = ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
        if (totals.containsKey(e.uid)) {
          totals[e.uid] = totals[e.uid]! + e.amount;
        }
      }
      return totals;
    } catch (_) {
      return {};
    }
  }

  // ── Get all members' monthly totals by TYPE (extended to support any month) ─
  Future<Map<String, Map<String, double>>> getAllMembersTypeTotalForMonth({
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
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      // result[uid][type] = total
      final Map<String, Map<String, double>> result = {
        for (final uid in memberUids) uid: {},
      };
      for (final doc in snap.docs) {
        final e = ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
        if (result.containsKey(e.uid)) {
          result[e.uid]![e.categoryType] =
              (result[e.uid]![e.categoryType] ?? 0) + e.amount;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  // ── Get all members' daily totals by TYPE ─────────────────────────────────
  Future<Map<String, Map<String, double>>> getAllMembersTypeTotalForDay({
    required String groupId,
    required List<String> memberUids,
    required DateTime day,
  }) async {
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      final Map<String, Map<String, double>> result = {
        for (final uid in memberUids) uid: {},
      };
      for (final doc in snap.docs) {
        final e = ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
        if (result.containsKey(e.uid)) {
          result[e.uid]![e.categoryType] =
              (result[e.uid]![e.categoryType] ?? 0) + e.amount;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  // ── Get own expenses for a specific month ──────────────────────────────────
  Stream<List<ExpenseModel>> getMyMonthlyExpenses({
    required String groupId,
    required String uid,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .where('uid', isEqualTo: uid)
        .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('date', isLessThan: end.toIso8601String())
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ExpenseModel.fromMap(d.data() as Map<String, dynamic>))
            .toList());
  }

  // ── Get own expenses for a specific week ───────────────────────────────────
  Stream<List<ExpenseModel>> getMyWeeklyExpenses({
    required String groupId,
    required String uid,
    required DateTime weekStart,
  }) {
    final end = weekStart.add(const Duration(days: 7));
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .where('uid', isEqualTo: uid)
        .where('date', isGreaterThanOrEqualTo: weekStart.toIso8601String())
        .where('date', isLessThan: end.toIso8601String())
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ExpenseModel.fromMap(d.data() as Map<String, dynamic>))
            .toList());
  }

  // ── Get friend's monthly type-wise summary ─────────────────────────────────
  Future<Map<String, double>> getFriendMonthlyTypeSummary({
    required String groupId,
    required String uid,
    required DateTime month,
  }) async {
    try {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .where('uid', isEqualTo: uid)
          .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      final Map<String, double> summary = {};
      for (final doc in snap.docs) {
        final e = ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
        summary[e.categoryType] =
            (summary[e.categoryType] ?? 0) + e.amount;
      }
      return summary;
    } catch (_) {
      return {};
    }
  }

  // ── Get all members' weekly totals (for leaderboard) ─────────────────────
  Future<Map<String, double>> getAllMembersWeeklyTotal({
    required String groupId,
    required List<String> memberUids,
    required DateTime weekStart,
  }) async {
    try {
      final end = weekStart.add(const Duration(days: 7));
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: weekStart.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      final Map<String, double> totals = {for (final uid in memberUids) uid: 0};
      for (final doc in snap.docs) {
        final e = ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
        if (totals.containsKey(e.uid)) totals[e.uid] = totals[e.uid]! + e.amount;
      }
      return totals;
    } catch (_) { return {}; }
  }

  // ── Get all members' weekly totals by TYPE ─────────────────────────────────
  Future<Map<String, Map<String, double>>> getAllMembersTypeTotalForWeek({
    required String groupId,
    required List<String> memberUids,
    required DateTime weekStart,
  }) async {
    try {
      final end = weekStart.add(const Duration(days: 7));
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: weekStart.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      final Map<String, Map<String, double>> result = {for (final uid in memberUids) uid: {}};
      for (final doc in snap.docs) {
        final e = ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
        if (result.containsKey(e.uid)) {
          result[e.uid]![e.categoryType] = (result[e.uid]![e.categoryType] ?? 0) + e.amount;
        }
      }
      return result;
    } catch (_) { return {}; }
  }

  // ── Get all members' monthly totals (for leaderboard) ─────────────────────
  Future<Map<String, double>> getAllMembersMonthlyTotal({
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
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      final Map<String, double> totals = {for (final uid in memberUids) uid: 0};
      for (final doc in snap.docs) {
        final e = ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
        if (totals.containsKey(e.uid)) {
          totals[e.uid] = totals[e.uid]! + e.amount;
        }
      }
      return totals;
    } catch (_) {
      return {};
    }
  }

  // ── Get all members' monthly totals per TYPE (for leaderboard) ─────────────
  Future<Map<String, Map<String, double>>> getAllMembersTypeMonthlyTotal({
    required String groupId,
    required List<String> memberUids,
    required List<String> types,
    required DateTime month,
  }) async {
    try {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
          .where('date', isLessThan: end.toIso8601String())
          .get();
      // typeTotals[type][uid] = amount
      final Map<String, Map<String, double>> typeTotals = {
        for (final t in types) t: {for (final uid in memberUids) uid: 0},
      };
      for (final doc in snap.docs) {
        final e = ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
        if (typeTotals.containsKey(e.categoryType) &&
            typeTotals[e.categoryType]!.containsKey(e.uid)) {
          typeTotals[e.categoryType]![e.uid] =
              typeTotals[e.categoryType]![e.uid]! + e.amount;
        }
      }
      return typeTotals;
    } catch (_) {
      return {};
    }
  }

  // ── Cleanup old data (called on app open) ──────────────────────────────────
  Future<void> cleanupOldExpenses(String groupId) async {
    try {
      final sixMonthsAgo =
          DateTime.now().subtract(const Duration(days: 180));
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .where('date', isLessThan: sixMonthsAgo.toIso8601String())
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
  static double totalFromList(List<ExpenseModel> expenses) =>
      expenses.fold(0, (sum, e) => sum + e.amount);

  static Map<String, double> typeSummaryFromList(
      List<ExpenseModel> expenses) {
    final Map<String, double> summary = {};
    for (final e in expenses) {
      summary[e.categoryType] =
          (summary[e.categoryType] ?? 0) + e.amount;
    }
    return summary;
  }

  static DateTime get currentMonthStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  static DateTime get currentWeekStart {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }
}
