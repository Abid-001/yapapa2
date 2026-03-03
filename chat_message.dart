class ScreentimeModel {
  final String id;
  final String uid;
  final String groupId;
  final DateTime date; // The day this record is for
  final int totalMinutes;
  final Map<String, int> appUsage; // appName -> minutes
  final int? dailyLimitMinutes; // User's self-set limit

  ScreentimeModel({
    required this.id,
    required this.uid,
    required this.groupId,
    required this.date,
    required this.totalMinutes,
    required this.appUsage,
    this.dailyLimitMinutes,
  });

  bool get isOverLimit =>
      dailyLimitMinutes != null && totalMinutes > dailyLimitMinutes!;

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'groupId': groupId,
        'date': date.toIso8601String(),
        'totalMinutes': totalMinutes,
        'appUsage': appUsage,
        'dailyLimitMinutes': dailyLimitMinutes,
      };

  factory ScreentimeModel.fromMap(Map<String, dynamic> map) => ScreentimeModel(
        id: map['id'] ?? '',
        uid: map['uid'] ?? '',
        groupId: map['groupId'] ?? '',
        date: DateTime.parse(
            map['date'] ?? DateTime.now().toIso8601String()),
        totalMinutes: map['totalMinutes'] ?? 0,
        appUsage: Map<String, int>.from(map['appUsage'] ?? {}),
        dailyLimitMinutes: map['dailyLimitMinutes'],
      );

  String get formattedTotal {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
