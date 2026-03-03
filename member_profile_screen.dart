class ChatMessage {
  final String id;
  final String groupId;
  final String senderUid;
  final String senderName;
  final String text;
  final bool isPreset;
  final bool isFixed;
  final bool isDeleted;
  final String? editedText;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSender;
  final Map<String, String> reactions;   // uid → emoji
  final List<String> seenBy;             // uids who have seen this
  final DateTime timestamp;

  // ── Poll fields ────────────────────────────────────────────────────────────
  final bool isPoll;
  final String? pollQuestion;
  final List<String> pollOptions;
  final bool pollAllowMultiple;
  final Map<String, List<int>> pollVotes; // uid → list of selected option indices
  final bool pollIsPreset;
  final String? pollPresetId;

  // ── Link preview ──────────────────────────────────────────────────────────
  final Map<String, String>? linkPreview; // {url, title, description, image}

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
    this.replyToId,
    this.replyToText,
    this.replyToSender,
    this.reactions = const {},
    this.seenBy = const [],
    // poll
    this.isPoll = false,
    this.pollQuestion,
    this.pollOptions = const [],
    this.pollAllowMultiple = false,
    this.pollVotes = const {},
    this.pollIsPreset = false,
    this.pollPresetId,
    // link
    this.linkPreview,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'groupId': groupId,
      'senderUid': senderUid,
      'senderName': senderName,
      'text': text,
      'isPreset': isPreset,
      'isFixed': isFixed,
      'isDeleted': isDeleted,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
    if (editedText != null) map['editedText'] = editedText;
    if (replyToId != null) map['replyToId'] = replyToId;
    if (replyToText != null) map['replyToText'] = replyToText;
    if (replyToSender != null) map['replyToSender'] = replyToSender;
    if (reactions.isNotEmpty) map['reactions'] = reactions;
    if (seenBy.isNotEmpty) map['seenBy'] = seenBy;
    // poll
    if (isPoll) {
      map['isPoll'] = true;
      map['pollQuestion'] = pollQuestion;
      map['pollOptions'] = pollOptions;
      map['pollAllowMultiple'] = pollAllowMultiple;
      if (pollVotes.isNotEmpty) map['pollVotes'] = pollVotes.map((k, v) => MapEntry(k, v));
      if (pollIsPreset) map['pollIsPreset'] = true;
      if (pollPresetId != null) map['pollPresetId'] = pollPresetId;
    }
    if (linkPreview != null) map['linkPreview'] = linkPreview;
    return map;
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    // reactions
    Map<String, String> reactions = {};
    final rawR = map['reactions'];
    if (rawR is Map) reactions = Map<String, String>.from(rawR.map((k, v) => MapEntry(k.toString(), v.toString())));

    // seenBy (stored as map {uid: true} in RTDB)
    List<String> seenBy = [];
    final rawS = map['seenBy'];
    if (rawS is Map) seenBy = rawS.keys.map((k) => k.toString()).toList();
    else if (rawS is List) seenBy = rawS.map((e) => e.toString()).toList();

    // pollVotes
    Map<String, List<int>> pollVotes = {};
    final rawV = map['pollVotes'];
    if (rawV is Map) {
      rawV.forEach((k, v) {
        if (v is List) pollVotes[k.toString()] = v.map((i) => (i as num).toInt()).toList();
      });
    }

    // linkPreview
    Map<String, String>? linkPreview;
    final rawLP = map['linkPreview'];
    if (rawLP is Map) linkPreview = Map<String, String>.from(rawLP.map((k, v) => MapEntry(k.toString(), v.toString())));

    return ChatMessage(
      id: map['id'] ?? '',
      groupId: map['groupId'] ?? '',
      senderUid: map['senderUid'] ?? '',
      senderName: map['senderName'] ?? '',
      text: map['text'] ?? '',
      isPreset: map['isPreset'] ?? false,
      isFixed: map['isFixed'] ?? false,
      isDeleted: map['isDeleted'] ?? false,
      editedText: map['editedText'] as String?,
      replyToId: map['replyToId'] as String?,
      replyToText: map['replyToText'] as String?,
      replyToSender: map['replyToSender'] as String?,
      reactions: reactions,
      seenBy: seenBy,
      isPoll: map['isPoll'] ?? false,
      pollQuestion: map['pollQuestion'] as String?,
      pollOptions: List<String>.from(map['pollOptions'] ?? []),
      pollAllowMultiple: map['pollAllowMultiple'] ?? false,
      pollVotes: pollVotes,
      pollIsPreset: map['pollIsPreset'] ?? false,
      pollPresetId: map['pollPresetId'] as String?,
      linkPreview: linkPreview,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }

  bool get isExpired => DateTime.now().difference(timestamp).inDays >= 30;
}
