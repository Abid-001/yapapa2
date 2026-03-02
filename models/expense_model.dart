class ExpenseModel {
  final String id;
  final String uid;
  final String groupId;
  final double amount;
  final String categoryName; // User-defined name e.g. "Lunch at Dhanmondi"
  final String categoryType; // Admin-defined type e.g. "Food"
  final String? note;
  final DateTime date;
  final DateTime createdAt;

  ExpenseModel({
    required this.id,
    required this.uid,
    required this.groupId,
    required this.amount,
    required this.categoryName,
    required this.categoryType,
    this.note,
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'groupId': groupId,
        'amount': amount,
        'categoryName': categoryName,
        'categoryType': categoryType,
        'note': note,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ExpenseModel.fromMap(Map<String, dynamic> map) => ExpenseModel(
        id: map['id'] ?? '',
        uid: map['uid'] ?? '',
        groupId: map['groupId'] ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        categoryName: map['categoryName'] ?? '',
        categoryType: map['categoryType'] ?? '',
        note: map['note'],
        date: DateTime.parse(
            map['date'] ?? DateTime.now().toIso8601String()),
        createdAt: DateTime.parse(
            map['createdAt'] ?? DateTime.now().toIso8601String()),
      );
}
