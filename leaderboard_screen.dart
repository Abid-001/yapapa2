class MonthlyReminder {
  final String text;
  final int startDay; // 1–28
  final int endDay;   // 1–28, >= startDay

  MonthlyReminder({required this.text, required this.startDay, required this.endDay});

  Map<String, dynamic> toMap() => {'text': text, 'startDay': startDay, 'endDay': endDay};

  factory MonthlyReminder.fromMap(Map<String, dynamic> m) => MonthlyReminder(
    text: m['text'] ?? '',
    startDay: m['startDay'] ?? 1,
    endDay: m['endDay'] ?? 10,
  );
}

class GroupModel {
  final String groupId;
  final String inviteCode;
  final String adminUid;
  final List<String> memberUids;
  final List<String> expenseTypes;
  final DateTime createdAt;
  final int defaultScreentimeMinutes;
  final List<MonthlyReminder> monthlyReminders; // up to 3

  GroupModel({
    required this.groupId,
    required this.inviteCode,
    required this.adminUid,
    required this.memberUids,
    required this.expenseTypes,
    required this.createdAt,
    this.defaultScreentimeMinutes = 180,
    this.monthlyReminders = const [],
  });

  Map<String, dynamic> toMap() => {
    'groupId': groupId,
    'inviteCode': inviteCode,
    'adminUid': adminUid,
    'memberUids': memberUids,
    'expenseTypes': expenseTypes,
    'createdAt': createdAt.toIso8601String(),
    'defaultScreentimeMinutes': defaultScreentimeMinutes,
    'monthlyReminders': monthlyReminders.map((r) => r.toMap()).toList(),
  };

  factory GroupModel.fromMap(Map<String, dynamic> map) {
    List<MonthlyReminder> reminders = [];
    final raw = map['monthlyReminders'];
    if (raw is List) {
      reminders = raw
          .whereType<Map>()
          .map((m) => MonthlyReminder.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }
    return GroupModel(
      groupId: map['groupId'] ?? '',
      inviteCode: map['inviteCode'] ?? '',
      adminUid: map['adminUid'] ?? '',
      memberUids: List<String>.from(map['memberUids'] ?? []),
      expenseTypes: List<String>.from(map['expenseTypes'] ?? []),
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      defaultScreentimeMinutes: map['defaultScreentimeMinutes'] ?? 180,
      monthlyReminders: reminders,
    );
  }

  GroupModel copyWith({
    String? adminUid,
    List<String>? memberUids,
    List<String>? expenseTypes,
    int? defaultScreentimeMinutes,
    List<MonthlyReminder>? monthlyReminders,
  }) => GroupModel(
    groupId: groupId,
    inviteCode: inviteCode,
    adminUid: adminUid ?? this.adminUid,
    memberUids: memberUids ?? this.memberUids,
    expenseTypes: expenseTypes ?? this.expenseTypes,
    createdAt: createdAt,
    defaultScreentimeMinutes: defaultScreentimeMinutes ?? this.defaultScreentimeMinutes,
    monthlyReminders: monthlyReminders ?? this.monthlyReminders,
  );
}
