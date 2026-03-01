class ChatMessage {
  final String id;
  final String groupId;
  final String senderUid;
  final String senderName;
  final String text;
  final bool isPreset; // true if this was a preset notification message
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderUid,
    required this.senderName,
    required this.text,
    required this.isPreset,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'groupId': groupId,
        'senderUid': senderUid,
        'senderName': senderName,
        'text': text,
        'isPreset': isPreset,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] ?? '',
        groupId: map['groupId'] ?? '',
        senderUid: map['senderUid'] ?? '',
        senderName: map['senderName'] ?? '',
        text: map['text'] ?? '',
        isPreset: map['isPreset'] ?? false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            map['timestamp'] ?? 0),
      );

  bool get isExpired =>
      DateTime.now().difference(timestamp).inDays >= 30;
}
