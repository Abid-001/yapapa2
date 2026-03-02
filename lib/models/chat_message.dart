class ChatMessage {
  final String id;
  final String groupId;
  final String senderUid;
  final String senderName;
  final String text;
  final bool isPreset; // true if this was a preset notification message
  final bool isFixed;  // true if it's an admin-set fixed preset (shows for everyone)
  final bool isDeleted; // removed for everyone
  final String? editedText; // non-null if message was edited
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderUid,
    required this.senderName,
    required this.text,
    required this.isPreset,
    this.isFixed = false,
    this.isDeleted = false,
    this.editedText,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'groupId': groupId,
        'senderUid': senderUid,
        'senderName': senderName,
        'text': text,
        'isPreset': isPreset,
        'isFixed': isFixed,
        'isDeleted': isDeleted,
        if (editedText != null) 'editedText': editedText,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] ?? '',
        groupId: map['groupId'] ?? '',
        senderUid: map['senderUid'] ?? '',
        senderName: map['senderName'] ?? '',
        text: map['text'] ?? '',
        isPreset: map['isPreset'] ?? false,
        isFixed: map['isFixed'] ?? false,
        isDeleted: map['isDeleted'] ?? false,
        editedText: map['editedText'] as String?,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            map['timestamp'] ?? 0),
      );

  bool get isExpired =>
      DateTime.now().difference(timestamp).inDays >= 30;
}
