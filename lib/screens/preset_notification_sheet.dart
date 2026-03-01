import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/preset_message.dart';

class PresetNotificationSheet extends StatefulWidget {
  const PresetNotificationSheet({super.key});

  @override
  State<PresetNotificationSheet> createState() =>
      _PresetNotificationSheetState();
}

class _PresetNotificationSheetState
    extends State<PresetNotificationSheet> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _sending = false;
  String? _sentMessage;
  bool _showAddField = false;
  final _addCtrl = TextEditingController();
  String? _addError;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendPreset(
      PresetMessage preset, String senderName, String groupId) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _sentMessage = null;
    });

    try {
      // Write a notification record to Firestore
      // All group members' apps will pick this up via a stream
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('notifications')
          .add({
        'type': 'preset',
        'text': preset.text,
        'senderName': senderName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Also post to chat as system message
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .add({
        'id': '',
        'groupId': groupId,
        'senderUid': 'system',
        'senderName': senderName,
        'text': preset.text,
        'isPreset': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      if (mounted) {
        setState(() {
          _sending = false;
          _sentMessage = preset.text;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addCustomPreset(String groupId, String creatorUid) async {
    final text = _addCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _addError = 'Please type a message.');
      return;
    }
    if (text.length > 120) {
      setState(() => _addError = 'Message too long (max 120 chars).');
      return;
    }

    try {
      final docRef = _db
          .collection('groups')
          .doc(groupId)
          .collection('presets')
          .doc();
      final preset = PresetMessage(
        id: docRef.id,
        groupId: groupId,
        createdByUid: creatorUid,
        text: text,
        isDefault: false,
      );
      await docRef.set(preset.toMap());
      if (mounted) {
        setState(() {
          _showAddField = false;
          _addError = null;
        });
        _addCtrl.clear();
      }
    } catch (_) {}
  }

  Future<void> _deletePreset(String groupId, String presetId) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('presets')
          .doc(presetId)
          .delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final group = auth.currentGroup;
    if (user == null || group == null) return const SizedBox.shrink();

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle + title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '🔔 Send Notification',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showAddField = !_showAddField),
                      icon: Icon(
                        _showAddField ? Icons.close : Icons.add_rounded,
                        size: 16,
                      ),
                      label: Text(_showAddField ? 'Cancel' : 'Add New'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        textStyle: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap any message to send to all friends instantly',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),

          // Success banner
          if (_sentMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.accent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppTheme.accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sent: "$_sentMessage"',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.accent,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Add custom field
          if (_showAddField)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addCtrl,
                          decoration: InputDecoration(
                            hintText: 'Type your custom message...',
                            errorText: _addError,
                          ),
                          maxLength: 120,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () =>
                            _addCustomPreset(group.groupId, user.uid),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          minimumSize: Size.zero,
                        ),
                        child: const Icon(Icons.check_rounded, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
          const Divider(color: AppTheme.divider, height: 1),

          // Presets list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('groups')
                  .doc(group.groupId)
                  .collection('presets')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary, strokeWidth: 2),
                  );
                }

                final presets = snapshot.data!.docs
                    .map((d) =>
                        PresetMessage.fromMap(d.data() as Map<String, dynamic>))
                    .toList()
                  ..sort((a, b) {
                    if (a.isDefault && !b.isDefault) return -1;
                    if (!a.isDefault && b.isDefault) return 1;
                    return 0;
                  });

                if (presets.isEmpty) {
                  return Center(
                    child: Text(
                      'No preset messages yet. Add one!',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppTheme.textHint),
                    ),
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                      16, 12, 16, bottomInset + 24),
                  itemCount: presets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final preset = presets[i];
                    final canDelete = !preset.isDefault &&
                        (preset.createdByUid == user.uid ||
                            user.isAdmin);
                    return _PresetTile(
                      preset: preset,
                      isSending: _sending,
                      onSend: () => _sendPreset(
                          preset, user.username, group.groupId),
                      onDelete: canDelete
                          ? () => _deletePreset(
                              group.groupId, preset.id)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final PresetMessage preset;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback? onDelete;

  const _PresetTile({
    required this.preset,
    required this.isSending,
    required this.onSend,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSending ? null : onSend,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: preset.isDefault
                ? AppTheme.primary.withOpacity(0.15)
                : AppTheme.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: preset.isDefault
                    ? AppTheme.primary.withOpacity(0.15)
                    : AppTheme.surfaceHighlight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  preset.isDefault ? '📢' : '✏️',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                preset.text,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (onDelete != null)
              GestureDetector(
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppTheme.textHint),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSending
                    ? AppTheme.surfaceHighlight
                    : AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isSending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary),
                    )
                  : Text(
                      'Send',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
