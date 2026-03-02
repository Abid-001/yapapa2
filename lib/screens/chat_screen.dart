import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../models/user_model.dart';
import '../widgets/common_widgets.dart';
import 'member_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _listenMessages();
    _cleanExpiredMessages();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _groupId =>
      context.read<AuthService>().currentGroup?.groupId ?? '';

  void _listenMessages() {
    if (_groupId.isEmpty) return;
    _dbRef
        .child('chats/$_groupId/messages')
        .orderByChild('timestamp')
        .limitToLast(100)
        .onValue
        .listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data == null) {
        setState(() {
          _messages = [];
          _loading = false;
        });
        return;
      }

      final map = Map<String, dynamic>.from(data as Map);
      final msgs = map.entries
          .map((e) {
            try {
              final m = Map<String, dynamic>.from(e.value as Map);
              m['id'] = e.key;
              return ChatMessage.fromMap(m);
            } catch (_) {
              return null;
            }
          })
          .whereType<ChatMessage>()
          .where((m) => !m.isExpired)
          // Only show normal chat messages OR admin-fixed preset notifications
          .where((m) => !m.isPreset || (m.isPreset && (m.isFixed)))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() {
        _messages = msgs;
        _loading = false;
      });

      // Scroll to bottom after messages load
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });
  }

  Future<void> _cleanExpiredMessages() async {
    if (_groupId.isEmpty) return;
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      final snap = await _dbRef
          .child('chats/$_groupId/messages')
          .orderByChild('timestamp')
          .endAt(cutoff)
          .get();
      if (snap.exists) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        for (final key in map.keys) {
          await _dbRef
              .child('chats/$_groupId/messages/$key')
              .remove();
        }
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _sending = true);
    _msgCtrl.clear();

    try {
      final ref =
          _dbRef.child('chats/$_groupId/messages').push();
      final msg = ChatMessage(
        id: ref.key ?? '',
        groupId: _groupId,
        senderUid: user.uid,
        senderName: user.username,
        text: text,
        isPreset: false,
        timestamp: DateTime.now(),
      );
      await ref.set(msg.toMap());
    } catch (_) {}

    if (mounted) setState(() => _sending = false);
  }


  Future<void> _editMessage(ChatMessage msg, String newText) async {
    if (newText.trim().isEmpty) return;
    try {
      await _dbRef.child('chats/$_groupId/messages/${msg.id}').update({
        'text': newText.trim(),
        'editedText': newText.trim(),
      });
    } catch (_) {}
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    try {
      await _dbRef.child('chats/$_groupId/messages/${msg.id}').update({
        'isDeleted': true,
        'text': 'This message was removed.',
      });
    } catch (_) {}
  }

  void _showMessageOptions(BuildContext context, ChatMessage msg) {
    final canDelete = DateTime.now().difference(msg.timestamp).inMinutes < 60;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
            title: Text('Edit message', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              _showEditDialog(context, msg);
            },
          ),
          if (canDelete) ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
            title: Text('Remove for everyone', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.error)),
            onTap: () {
              Navigator.pop(context);
              _deleteMessage(msg);
            },
          ),
        ]),
      ),
    );
  }

  void _showEditDialog(BuildContext context, ChatMessage msg) {
    final ctrl = TextEditingController(text: msg.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit message', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: TextField(controller: ctrl, autofocus: true, maxLines: null,
          decoration: const InputDecoration(hintText: 'Edit your message...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { _editMessage(msg, ctrl.text); Navigator.pop(ctx); },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Auto-delete notice
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppTheme.textHint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Messages older than 1 month are automatically deleted',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppTheme.textHint),
                ),
              ),
            ],
          ),
        ),

        // Messages list
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2))
              : _messages.isEmpty
                  ? const EmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'No messages yet',
                      subtitle: 'Say hello to your group!',
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final msg = _messages[i];
                        final isMe = msg.senderUid == user.uid;
                        final showDateDivider = i == 0 ||
                            !_isSameDay(
                              _messages[i - 1].timestamp,
                              msg.timestamp,
                            );
                        // Show time only on the LAST consecutive message
                        // from the same sender at the same minute
                        final isLast = i == _messages.length - 1;
                        final nextMsg = isLast ? null : _messages[i + 1];
                        final showTime = isLast ||
                            nextMsg!.senderUid != msg.senderUid ||
                            !_isSameMinute(msg.timestamp, nextMsg.timestamp);
                        return Column(
                          children: [
                            if (showDateDivider)
                              _DateDivider(date: msg.timestamp),
                            _MessageBubble(
                              message: msg,
                              isMe: isMe,
                              showTime: showTime,
                              onLongPress: isMe && !msg.isDeleted
                                ? () => _showMessageOptions(context, msg)
                                : null,
                            ),
                          ],
                        );
                      },
                    ),
        ),

        // Input bar
        _ChatInput(
          controller: _msgCtrl,
          focusNode: _focusNode,
          sending: _sending,
          onSend: _sendMessage,
        ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isSameMinute(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day &&
      a.hour == b.hour && a.minute == b.minute;
}

// ─── Message Bubble ───────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showTime;
  final VoidCallback? onLongPress;

  const _MessageBubble({required this.message, required this.isMe, this.showTime = true, this.onLongPress});

  void _openProfile(BuildContext context) {
    // Look up member by senderUid from Firestore users collection
    final db = FirebaseFirestore.instance;
    db.collection('users').doc(message.senderUid).get().then((doc) {
      if (doc.exists && context.mounted) {
        final user = UserModel.fromMap(doc.data() as Map<String, dynamic>);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MemberProfileScreen(member: user)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeStr =
        DateFormat('HH:mm').format(message.timestamp);

    if (message.isPreset) {
      return _PresetMessageBubble(message: message);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar (only for others) — tap to open profile
          if (!isMe) ...[
            GestureDetector(
              onTap: () => _openProfile(context),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    message.senderName.isNotEmpty
                        ? message.senderName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],

          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: GestureDetector(
                      onTap: () => _openProfile(context),
                      child: Text(
                        message.senderName,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.68,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: message.isDeleted
                          ? AppTheme.surfaceHighlight
                          : isMe ? AppTheme.primary : AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.isDeleted ? 'This message was removed.' : message.text,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: message.isDeleted
                                ? AppTheme.textHint
                                : isMe ? Colors.white : AppTheme.textPrimary,
                            fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                        if (!message.isDeleted && message.editedText != null)
                          Text(
                            '(edited)',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: isMe ? Colors.white60 : AppTheme.textHint,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (showTime) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      timeStr,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppTheme.textHint,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (isMe) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ─── Preset Message Bubble (system-style) ─────────────────────────────────────
class _PresetMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _PresetMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(message.timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accent.withOpacity(0.25)),
          ),
          child: Column(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.notifications_active_rounded, size: 13, color: AppTheme.accent),
              const SizedBox(width: 5),
              Text('${message.senderName} sent a notification',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.accent)),
            ]),
            const SizedBox(height: 5),
            Text(message.text, textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary, fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text(timeStr, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textHint)),
          ]),
        ),
      ),
    );
  }
}

// ─── Date Divider ─────────────────────────────────────────────────────────────
class _DateDivider extends StatelessWidget {
  final DateTime date;

  const _DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay =
        DateTime(date.year, date.month, date.day);

    String label;
    if (msgDay == today) {
      label = 'Today';
    } else if (msgDay == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('d MMM yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppTheme.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textHint,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppTheme.divider)),
        ],
      ),
    );
  }
}

// ─── Chat Input Bar ───────────────────────────────────────────────────────────
class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: 4,
              minLines: 1,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                counterText: '',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => onSend(),
              inputFormatters: [
                LengthLimitingTextInputFormatter(500),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: sending ? null : AppTheme.primaryGradient,
                color: sending ? AppTheme.surfaceHighlight : null,
                shape: BoxShape.circle,
                boxShadow: sending
                    ? []
                    : [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: sending
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primary),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
