import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/preset_message.dart';

// ── Preset logic:
// • isFixed=true presets: Admin-only editable; visible to ALL users in their sheet; 
//   these appear in chat as "admin notifications"
// • isFixed=false presets: Created by a user; only visible to that user (personal shortcuts)
// • isDefault=true is the old legacy field — treat like isFixed for display

class PresetNotificationSheet extends StatefulWidget {
  const PresetNotificationSheet({super.key});
  @override
  State<PresetNotificationSheet> createState() => _PresetNotificationSheetState();
}

class _PresetNotificationSheetState extends State<PresetNotificationSheet> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _sending = false;
  String? _sentMessage;
  bool _showAddField = false;
  final _addCtrl = TextEditingController();
  String? _addError;
  // Admin can edit a fixed preset
  String? _editingPresetId;
  final _editCtrl = TextEditingController();

  @override
  void dispose() { _addCtrl.dispose(); _editCtrl.dispose(); super.dispose(); }

  Future<void> _sendPreset(PresetMessage preset, String senderName, String senderUid, String groupId) async {
    if (_sending) return;
    setState(() { _sending = true; _sentMessage = null; });
    try {
      // Write notification to Firestore (all devices pick it up for push)
      await _db.collection('groups').doc(groupId).collection('notifications').add({
        'type': 'preset',
        'text': preset.text,
        'senderName': senderName,
        'senderUid': senderUid,
        'isFixed': preset.isDefault,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      // Only fixed (admin) presets appear in chat for everyone
      if (preset.isDefault) {
        final msgRef = FirebaseDatabase.instance.ref('chats/$groupId/messages').push();
        await msgRef.set({
          'id': msgRef.key ?? '',
          'groupId': groupId,
          'senderUid': senderUid,
          'senderName': senderName,
          'text': preset.text,
          'isPreset': true,
          'isFixed': true,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
      if (mounted) setState(() { _sending = false; _sentMessage = preset.text; });
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addPersonalPreset(String groupId, String creatorUid) async {
    final text = _addCtrl.text.trim();
    if (text.isEmpty) { setState(() => _addError = 'Please type a message.'); return; }
    if (text.length > 120) { setState(() => _addError = 'Message too long (max 120 chars).'); return; }
    try {
      final docRef = _db.collection('groups').doc(groupId).collection('presets').doc();
      await docRef.set(PresetMessage(id: docRef.id, groupId: groupId, createdByUid: creatorUid, text: text, isDefault: false).toMap());
      if (mounted) { setState(() { _showAddField = false; _addError = null; }); _addCtrl.clear(); }
    } catch (_) {}
  }

  Future<void> _saveEditPreset(String groupId, String presetId) async {
    final text = _editCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).collection('presets').doc(presetId).update({'text': text});
      if (mounted) setState(() => _editingPresetId = null);
    } catch (_) {}
  }

  Future<void> _deletePreset(String groupId, String presetId) async {
    try { await _db.collection('groups').doc(groupId).collection('presets').doc(presetId).delete(); } catch (_) {}
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
      decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Column(children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('🔔 Send Notification', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            TextButton.icon(
              onPressed: () => setState(() { _showAddField = !_showAddField; _addError = null; }),
              icon: Icon(_showAddField ? Icons.close : Icons.add_rounded, size: 16),
              label: Text(_showAddField ? 'Cancel' : 'My Preset'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary, textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600), padding: EdgeInsets.zero),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Fixed notifications (📢) go to everyone\'s chat. Your personal ones (✏️) are private shortcuts.',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
        ])),

        if (_sentMessage != null)
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.accent.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 18), const SizedBox(width: 8),
              Expanded(child: Text('Sent: "$_sentMessage"', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.accent), overflow: TextOverflow.ellipsis)),
            ]),
          )),

        if (_showAddField)
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [
            Expanded(child: TextField(controller: _addCtrl, decoration: InputDecoration(hintText: 'Your personal shortcut message...', errorText: _addError), maxLength: 120, textCapitalization: TextCapitalization.sentences)),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => _addPersonalPreset(group.groupId, user.uid),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), minimumSize: Size.zero),
              child: const Icon(Icons.check_rounded, size: 18),
            ),
          ])),

        const SizedBox(height: 8),
        const Divider(color: AppTheme.divider, height: 1),

        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: _db.collection('groups').doc(group.groupId).collection('presets').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2));

            final allPresets = snapshot.data!.docs.map((d) => PresetMessage.fromMap(d.data() as Map<String, dynamic>)).toList();

            // Fixed presets (isDefault=true): visible to ALL — admins can edit/manage
            final fixedPresets = allPresets.where((p) => p.isDefault).toList()
              ..sort((a, b) => a.id.compareTo(b.id));

            // Personal presets (isDefault=false): visible only to creator
            final myPresets = allPresets.where((p) => !p.isDefault && p.createdByUid == user.uid).toList();

            // Seed defaults if none exist
            if (fixedPresets.isEmpty && user.isAdmin) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _seedDefaults(group.groupId));
            }

            final sections = <Widget>[];

            // ── Section: Fixed / Admin Presets
            sections.add(Padding(padding: const EdgeInsets.fromLTRB(0, 12, 0, 8), child: Row(children: [
              Text('📢 Fixed Notifications', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
              if (user.isAdmin) ...[const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showAddFixedDialog(context, group.groupId, user.uid),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text('+ Add', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary))),
                )],
            ])));

            if (fixedPresets.isEmpty) {
              sections.add(Text('No fixed notifications yet.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textHint)));
            } else {
              for (final preset in fixedPresets) {
                sections.add(Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _editingPresetId == preset.id
                    ? _EditPresetRow(ctrl: _editCtrl, onSave: () => _saveEditPreset(group.groupId, preset.id), onCancel: () => setState(() => _editingPresetId = null))
                    : _PresetTile(
                        preset: preset, isSending: _sending, isAdmin: user.isAdmin,
                        onSend: () => _sendPreset(preset, user.username, user.uid, group.groupId),
                        onEdit: user.isAdmin ? () { _editCtrl.text = preset.text; setState(() => _editingPresetId = preset.id); } : null,
                        onDelete: user.isAdmin ? () => _deletePreset(group.groupId, preset.id) : null,
                      ),
                ));
              }
            }

            // ── Section: My Personal Presets
            sections.add(Padding(padding: const EdgeInsets.fromLTRB(0, 16, 0, 8), child:
              Text('✏️ My Personal Presets', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary))));

            if (myPresets.isEmpty) {
              sections.add(Text('No personal presets. Tap "My Preset" to add one.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textHint)));
            } else {
              for (final preset in myPresets) {
                sections.add(Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PresetTile(
                    preset: preset, isSending: _sending, isAdmin: user.isAdmin,
                    onSend: () => _sendPreset(preset, user.username, user.uid, group.groupId),
                    onDelete: () => _deletePreset(group.groupId, preset.id),
                  ),
                ));
              }
            }

            return ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 24), children: sections);
          },
        )),
      ]),
    );
  }

  void _showAddFixedDialog(BuildContext context, String groupId, String creatorUid) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('Add Fixed Notification', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'e.g. Meeting time! Sob ashis.'), maxLength: 120, textCapitalization: TextCapitalization.sentences, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final text = ctrl.text.trim();
            if (text.isEmpty) return;
            final docRef = _db.collection('groups').doc(groupId).collection('presets').doc();
            await docRef.set(PresetMessage(id: docRef.id, groupId: groupId, createdByUid: creatorUid, text: text, isDefault: true).toMap());
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ));
  }

  Future<void> _seedDefaults(String groupId) async {
    final snap = await _db.collection('groups').doc(groupId).collection('presets').where('isDefault', isEqualTo: true).limit(1).get();
    if (snap.docs.isNotEmpty) return;
    final defaults = PresetMessage.defaults(groupId);
    final batch = _db.batch();
    for (final p in defaults) {
      final ref = _db.collection('groups').doc(groupId).collection('presets').doc(p.id);
      batch.set(ref, p.toMap());
    }
    await batch.commit();
  }
}

class _EditPresetRow extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSave, onCancel;
  const _EditPresetRow({required this.ctrl, required this.onSave, required this.onCancel});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Edit message...'), autofocus: true, maxLength: 120)),
      const SizedBox(width: 8),
      IconButton(icon: const Icon(Icons.check_rounded, color: AppTheme.accent), onPressed: onSave),
      IconButton(icon: const Icon(Icons.close_rounded, color: AppTheme.textHint), onPressed: onCancel),
    ]);
  }
}

class _PresetTile extends StatelessWidget {
  final PresetMessage preset;
  final bool isSending, isAdmin;
  final VoidCallback onSend;
  final VoidCallback? onDelete, onEdit;
  const _PresetTile({required this.preset, required this.isSending, required this.isAdmin, required this.onSend, this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSending ? null : onSend,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: preset.isDefault ? AppTheme.primary.withOpacity(0.15) : AppTheme.divider),
        ),
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(color: preset.isDefault ? AppTheme.primary.withOpacity(0.15) : AppTheme.surfaceHighlight, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(preset.isDefault ? '📢' : '✏️', style: const TextStyle(fontSize: 16)))),
          const SizedBox(width: 12),
          Expanded(child: Text(preset.text, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w500))),
          const SizedBox(width: 8),
          if (onEdit != null)
            GestureDetector(onTap: onEdit, child: Padding(padding: const EdgeInsets.only(right: 8), child: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primary))),
          if (onDelete != null)
            GestureDetector(onTap: onDelete, child: Padding(padding: const EdgeInsets.only(right: 8), child: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.textHint))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: isSending ? AppTheme.surfaceHighlight : AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: isSending
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
              : Text('Send', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
          ),
        ]),
      ),
    );
  }
}
