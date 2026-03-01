// ─────────────────────────────────────────────
// models/user_model.dart
// ─────────────────────────────────────────────
class UserModel {
  final String uid;
  final String username;
  final String groupId;
  final bool isAdmin;
  final DateTime joinedAt;

  UserModel({
    required this.uid,
    required this.username,
    required this.groupId,
    required this.isAdmin,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'username': username,
        'groupId': groupId,
        'isAdmin': isAdmin,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        uid: map['uid'] ?? '',
        username: map['username'] ?? '',
        groupId: map['groupId'] ?? '',
        isAdmin: map['isAdmin'] ?? false,
        joinedAt: DateTime.parse(
            map['joinedAt'] ?? DateTime.now().toIso8601String()),
      );

  UserModel copyWith({String? username, bool? isAdmin}) => UserModel(
        uid: uid,
        username: username ?? this.username,
        groupId: groupId,
        isAdmin: isAdmin ?? this.isAdmin,
        joinedAt: joinedAt,
      );
}
