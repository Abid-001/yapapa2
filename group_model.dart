class PresetMessage {
  final String id;
  final String groupId;
  final String createdByUid;
  final String text;
  final bool isDefault; // Default presets cant be deleted

  PresetMessage({
    required this.id,
    required this.groupId,
    required this.createdByUid,
    required this.text,
    required this.isDefault,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'groupId': groupId,
        'createdByUid': createdByUid,
        'text': text,
        'isDefault': isDefault,
      };

  factory PresetMessage.fromMap(Map<String, dynamic> map) => PresetMessage(
        id: map['id'] ?? '',
        groupId: map['groupId'] ?? '',
        createdByUid: map['createdByUid'] ?? '',
        text: map['text'] ?? '',
        isDefault: map['isDefault'] ?? false,
      );

  static List<PresetMessage> defaults(String groupId) => [
        PresetMessage(
          id: 'default_1',
          groupId: groupId,
          createdByUid: 'system',
          text: 'Chabi lagbe, tora ke kothai asos?',
          isDefault: true,
        ),
        PresetMessage(
          id: 'default_2',
          groupId: groupId,
          createdByUid: 'system',
          text: 'Kew ashar shomoi nasta ante parbi?',
          isDefault: true,
        ),
        PresetMessage(
          id: 'default_3',
          groupId: groupId,
          createdByUid: 'system',
          text: 'Print korai anis keo!',
          isDefault: true,
        ),
        PresetMessage(
          id: 'default_4',
          groupId: groupId,
          createdByUid: 'system',
          text: 'Ajke ki plan ache?',
          isDefault: true,
        ),
        PresetMessage(
          id: 'default_5',
          groupId: groupId,
          createdByUid: 'system',
          text: 'Meeting time! Sob ashis.',
          isDefault: true,
        ),
      ];
}
