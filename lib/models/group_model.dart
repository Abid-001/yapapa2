class GroupModel {
  final String groupId;
  final String inviteCode;
  final String adminUid;
  final List<String> memberUids;
  final List<String> expenseTypes; // Admin-defined types e.g. Food, Transport
  final DateTime createdAt;

  GroupModel({
    required this.groupId,
    required this.inviteCode,
    required this.adminUid,
    required this.memberUids,
    required this.expenseTypes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'inviteCode': inviteCode,
        'adminUid': adminUid,
        'memberUids': memberUids,
        'expenseTypes': expenseTypes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory GroupModel.fromMap(Map<String, dynamic> map) => GroupModel(
        groupId: map['groupId'] ?? '',
        inviteCode: map['inviteCode'] ?? '',
        adminUid: map['adminUid'] ?? '',
        memberUids: List<String>.from(map['memberUids'] ?? []),
        expenseTypes: List<String>.from(map['expenseTypes'] ?? []),
        createdAt: DateTime.parse(
            map['createdAt'] ?? DateTime.now().toIso8601String()),
      );

  GroupModel copyWith({
    String? adminUid,
    List<String>? memberUids,
    List<String>? expenseTypes,
  }) =>
      GroupModel(
        groupId: groupId,
        inviteCode: inviteCode,
        adminUid: adminUid ?? this.adminUid,
        memberUids: memberUids ?? this.memberUids,
        expenseTypes: expenseTypes ?? this.expenseTypes,
        createdAt: createdAt,
      );
}
