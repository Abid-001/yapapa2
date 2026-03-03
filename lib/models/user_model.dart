class UserModel {
  final String uid;
  final String username;
  final String groupId;
  final bool isAdmin;
  final DateTime joinedAt;
  final String phoneNumber;
  final List<PersonalReminder> personalReminders;

  UserModel({
    required this.uid,
    required this.username,
    required this.groupId,
    required this.isAdmin,
    required this.joinedAt,
    this.phoneNumber = '',
    this.personalReminders = const [],
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'username': username,
        'groupId': groupId,
        'isAdmin': isAdmin,
        'joinedAt': joinedAt.toIso8601String(),
        'phoneNumber': phoneNumber,
        'personalReminders': personalReminders.map((r) => r.toMap()).toList(),
      };

  factory UserModel.fromMap(Map<String, dynamic> map) {
    List<PersonalReminder> reminders = [];
    final raw = map['personalReminders'];
    if (raw is List) {
      reminders = raw
        .whereType<Map>()
        .map((m) => PersonalReminder.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    }
    return UserModel(
      uid: map['uid'] ?? '',
      username: map['username'] ?? '',
      groupId: map['groupId'] ?? '',
      isAdmin: map['isAdmin'] ?? false,
      joinedAt: DateTime.parse(map['joinedAt'] ?? DateTime.now().toIso8601String()),
      phoneNumber: map['phoneNumber'] ?? '',
      personalReminders: reminders,
    );
  }

  UserModel copyWith({
    String? username,
    bool? isAdmin,
    String? phoneNumber,
    List<PersonalReminder>? personalReminders,
  }) =>
      UserModel(
        uid: uid,
        username: username ?? this.username,
        groupId: groupId,
        isAdmin: isAdmin ?? this.isAdmin,
        joinedAt: joinedAt,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        personalReminders: personalReminders ?? this.personalReminders,
      );
}

// ─── PersonalReminder ──────────────────────────────────────────────────────────
class PersonalReminder {
  final String id;
  final String text;
  final int startDay; // 1-28
  final int endDay;   // 1-28

  PersonalReminder({required this.id, required this.text, required this.startDay, required this.endDay});

  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'startDay': startDay, 'endDay': endDay};

  factory PersonalReminder.fromMap(Map<String, dynamic> m) => PersonalReminder(
    id: m['id'] ?? '',
    text: m['text'] ?? '',
    startDay: m['startDay'] ?? 1,
    endDay: m['endDay'] ?? 28,
  );
}
