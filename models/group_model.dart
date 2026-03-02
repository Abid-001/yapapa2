class GroupModel {
  final String groupId;
  final String inviteCode;
  final String adminUid;
  final List<String> memberUids;
  final List<String> expenseTypes;
  final DateTime createdAt;
  final int defaultScreentimeMinutes; // NEW: admin-set default limit (0 = no default)

  GroupModel({
    required this.groupId,
    required this.inviteCode,
    required this.adminUid,
    required this.memberUids,
    required this.expenseTypes,
    required this.createdAt,
    this.defaultScreentimeMinutes = 180, // 3 hours default
  });

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'inviteCode': inviteCode,
        'adminUid': adminUid,
        'memberUids': memberUids,
        'expenseTypes': expenseTypes,
        'createdAt': createdAt.toIso8601String(),
        'defaultScreentimeMinutes': defaultScreentimeMinutes,
      };

  factory GroupModel.fromMap(Map<String, dynamic> map) => GroupModel(
        groupId: map['groupId'] ?? '',
        inviteCode: map['inviteCode'] ?? '',
        adminUid: map['adminUid'] ?? '',
        memberUids: List<String>.from(map['memberUids'] ?? []),
        expenseTypes: List<String>.from(map['expenseTypes'] ?? []),
        createdAt: DateTime.parse(
            map['createdAt'] ?? DateTime.now().toIso8601String()),
        defaultScreentimeMinutes: map['defaultScreentimeMinutes'] ?? 180,
      );

  GroupModel copyWith({
    String? adminUid,
    List<String>? memberUids,
    List<String>? expenseTypes,
    int? defaultScreentimeMinutes,
  }) =>
      GroupModel(
        groupId: groupId,
        inviteCode: inviteCode,
        adminUid: adminUid ?? this.adminUid,
        memberUids: memberUids ?? this.memberUids,
        expenseTypes: expenseTypes ?? this.expenseTypes,
        createdAt: createdAt,
        defaultScreentimeMinutes:
            defaultScreentimeMinutes ?? this.defaultScreentimeMinutes,
      );
}
