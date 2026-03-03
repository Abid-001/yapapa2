import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../models/user_model.dart';
import '../widgets/common_widgets.dart';
import 'member_profile_screen.dart';

// ── WhatsApp-style colors ──────────────────────────────────────────────────────
const _kMyBubble     = Color(0xFF005C4B);
const _kTheirBubble  = Color(0xFF1F2C34);
const _kChatBg       = Color(0xFF0B141A);
const _kReplyMyBg    = Color(0xFF025144);
const _kReplyTheirBg = Color(0xFF182229);
const _kTickSent     = Color(0xFF8696A0);
const _kTickSeen     = Color(0xFF53BDEB);
const _kWaGreen      = Color(0xFF00A884);

// Single emoji check (no ASCII letters/digits, non-ASCII chars present)
bool _isSingleEmoji(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 8) return false;
  if (RegExp(r'[a-zA-Z0-9 ]').hasMatch(t)) return false;
  return t.runes.any((r) => r > 127);
}

const _kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

// ─────────────────────────────────────────────────────────────────────────────
// Exposes unread count to MainShell for the nav dot
final ValueNotifier<int> chatUnreadCount = ValueNotifier(0);

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  List<Map<String, dynamic>> _pins = [];
  List<Map<String, dynamic>> _presetPolls = [];
  bool _loading = true;
  bool _sending = false;
  bool _firstLoad = true;
  int? _firstUnreadIndex;
  ChatMessage? _replyTo;

  // Link preview state
  Map<String, String>? _linkPreview;
  Timer? _linkTimer;
  bool _fetchingLink = false;
  String? _lastCheckedUrl;

  // Share from other apps

  @override
  void initState() {
    super.initState();
    _listenMessages();
    _listenPins();
    _cleanExpiredMessages();
    _loadPresetPolls();
    _msgCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_onTextChanged);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _linkTimer?.cancel();
    super.dispose();
  }

  String get _groupId => context.read<AuthService>().currentGroup?.groupId ?? '';
  String get _myUid => context.read<AuthService>().currentUser?.uid ?? '';
  int get _memberCount => context.read<AuthService>().currentGroup?.memberUids.length ?? 1;



  // ── Link preview detection ────────────────────────────────────────────────────
  void _onTextChanged() {
    _linkTimer?.cancel();
    final text = _msgCtrl.text;
    final urlMatch = RegExp(r'https?://[^\s]+', caseSensitive: false).firstMatch(text);
    if (urlMatch == null) {
      if (_linkPreview != null) setState(() { _linkPreview = null; _lastCheckedUrl = null; });
      return;
    }
    final url = urlMatch.group(0)!;
    if (url == _lastCheckedUrl) return;
    _linkTimer = Timer(const Duration(milliseconds: 700), () => _fetchLinkPreview(url));
  }

  Future<void> _fetchLinkPreview(String url) async {
    if (_fetchingLink) return;
    _fetchingLink = true;
    _lastCheckedUrl = url;
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = response.body;
        String title = _extractMeta(body, 'og:title') ?? _extractMeta(body, 'title') ?? '';
        String desc  = _extractMeta(body, 'og:description') ?? _extractMeta(body, 'description') ?? '';
        String image = _extractMeta(body, 'og:image') ?? '';
        if (title.isNotEmpty || desc.isNotEmpty) {
          if (mounted) setState(() => _linkPreview = {'url': url, 'title': title, 'description': desc, 'image': image});
        }
      }
    } catch (_) {}
    _fetchingLink = false;
  }

  String? _extractMeta(String html, String name) {
    // og: properties
    var re = RegExp('property="$name"[^>]*content="([^"]*)"', caseSensitive: false);
    var m = re.firstMatch(html);
    if (m != null) return m.group(1);
    re = RegExp('content="([^"]*)"[^>]*property="$name"', caseSensitive: false);
    m = re.firstMatch(html);
    if (m != null) return m.group(1);
    // regular name=
    re = RegExp('name="$name"[^>]*content="([^"]*)"', caseSensitive: false);
    m = re.firstMatch(html);
    if (m != null) return m.group(1);
    // <title> tag
    if (name == 'title') {
      re = RegExp('<title[^>]*>([^<]+)</title>', caseSensitive: false);
      m = re.firstMatch(html);
      if (m != null) return m.group(1);
    }
    return null;
  }

  // ── Firebase listeners ────────────────────────────────────────────────────────
  void _listenMessages() {
    if (_groupId.isEmpty) return;
    _dbRef.child('chats/$_groupId/messages').orderByChild('timestamp').limitToLast(100).onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data == null) { setState(() { _messages = []; _loading = false; }); return; }
      final map = Map<String, dynamic>.from(data as Map);
      final msgs = map.entries.map((e) {
        try {
          final m = Map<String, dynamic>.from(e.value as Map);
          m['id'] = e.key;
          return ChatMessage.fromMap(m);
        } catch (_) { return null; }
      }).whereType<ChatMessage>().where((m) => !m.isExpired).where((m) => !m.isPreset || m.isFixed).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      setState(() { _messages = msgs; _loading = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_firstLoad) {
          _firstLoad = false;
          _scrollToFirstUnread();
        } else {
          _scrollToBottom();
        }
        _markAllSeen();
        _updateUnreadCount();
      });
    });
  }

  void _listenPins() {
    if (_groupId.isEmpty) return;
    _dbRef.child('chats/$_groupId/pins').onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data == null) { setState(() => _pins = []); return; }
      final map = Map<String, dynamic>.from(data as Map);
      final pins = map.entries.map((e) { final v = Map<String, dynamic>.from(e.value as Map); v['id'] = e.key; return v; }).toList()
        ..sort((a, b) => (b['pinnedAt'] as int? ?? 0).compareTo(a['pinnedAt'] as int? ?? 0));
      setState(() => _pins = pins);
    });
  }

  Future<void> _loadPresetPolls() async {
    if (_groupId.isEmpty) return;
    try {
      final snap = await _fs.collection('groups').doc(_groupId).collection('presetPolls').get();
      if (mounted) setState(() => _presetPolls = snap.docs.map((d) { final m = d.data(); m['id'] = d.id; return m; }).toList());
    } catch (_) {}
  }

  void _markAllSeen() {
    final uid = _myUid;
    if (uid.isEmpty) return;
    for (final msg in _messages) {
      if (msg.senderUid != uid && !msg.seenBy.contains(uid)) {
        _dbRef.child('chats/$_groupId/messages/${msg.id}/seenBy/$uid').set(true).ignore();
      }
    }
    if (_firstUnreadIndex != null && mounted) setState(() => _firstUnreadIndex = null);
    chatUnreadCount.value = 0;
  }

  void _updateUnreadCount() {
    final uid = _myUid;
    if (uid.isEmpty) return;
    final count = _messages.where((m) =>
      m.senderUid != uid && !m.seenBy.contains(uid) && !m.isPreset).length;
    chatUnreadCount.value = count;
  }

  void _scrollToFirstUnread() {
    final uid = _myUid;
    if (uid.isEmpty) { _scrollToBottom(); return; }
    final idx = _messages.indexWhere(
      (m) => m.senderUid != uid && !m.seenBy.contains(uid));
    if (idx < 0) {
      _scrollToBottom();
    } else {
      _firstUnreadIndex = idx;
      if (mounted) setState(() {});
      // Scroll so first unread is near top (leave some context above)
      final offset = (idx > 1 ? idx - 1 : 0) * 72.0;
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(offset.clamp(0, _scrollCtrl.position.maxScrollExtent));
      }
    }
  }

  Future<void> _cleanExpiredMessages() async {
    if (_groupId.isEmpty) return;
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      final snap = await _dbRef.child('chats/$_groupId/messages').orderByChild('timestamp').endAt(cutoff).get();
      if (snap.exists) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        for (final key in map.keys) await _dbRef.child('chats/$_groupId/messages/$key').remove();
      }
    } catch (_) {}
  }

  // ── Send message ──────────────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    final preview = _linkPreview;
    setState(() { _linkPreview = null; _lastCheckedUrl = null; });
    try {
      final ref = _dbRef.child('chats/$_groupId/messages').push();
      final reply = _replyTo;
      final msg = ChatMessage(
        id: ref.key ?? '', groupId: _groupId,
        senderUid: user.uid, senderName: user.username,
        text: text, isPreset: false,
        replyToId: reply?.id,
        replyToText: reply != null ? (reply.isDeleted ? 'Removed message' : reply.text) : null,
        replyToSender: reply?.senderName,
        linkPreview: preview,
        timestamp: DateTime.now(),
      );
      if (mounted) setState(() => _replyTo = null);
      await ref.set(msg.toMap());
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  // ── Send poll ─────────────────────────────────────────────────────────────────
  Future<void> _sendPoll({
    required String question,
    required List<String> options,
    required bool allowMultiple,
    String? presetId,
  }) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    try {
      final ref = _dbRef.child('chats/$_groupId/messages').push();
      final msg = ChatMessage(
        id: ref.key ?? '', groupId: _groupId,
        senderUid: user.uid, senderName: user.username,
        text: question, isPreset: false,
        isPoll: true, pollQuestion: question,
        pollOptions: options, pollAllowMultiple: allowMultiple,
        pollIsPreset: presetId != null, pollPresetId: presetId,
        timestamp: DateTime.now(),
      );
      await ref.set(msg.toMap());
    } catch (_) {}
  }

  // ── Vote on poll ──────────────────────────────────────────────────────────────
  Future<void> _vote(ChatMessage msg, int optionIdx) async {
    final uid = _myUid;
    if (uid.isEmpty) return;
    try {
      final current = List<int>.from(msg.pollVotes[uid] ?? []);
      if (msg.pollAllowMultiple) {
        if (current.contains(optionIdx)) current.remove(optionIdx);
        else current.add(optionIdx);
      } else {
        if (current.contains(optionIdx)) current.clear();
        else { current.clear(); current.add(optionIdx); }
      }
      await _dbRef.child('chats/$_groupId/messages/${msg.id}/pollVotes/$uid').set(current.isEmpty ? null : current);
    } catch (_) {}
  }

  // ── React ─────────────────────────────────────────────────────────────────────
  Future<void> _toggleReaction(ChatMessage msg, String emoji) async {
    final uid = _myUid;
    if (uid.isEmpty) return;
    try {
      final existing = msg.reactions[uid];
      if (existing == emoji) await _dbRef.child('chats/$_groupId/messages/${msg.id}/reactions/$uid').remove();
      else await _dbRef.child('chats/$_groupId/messages/${msg.id}/reactions/$uid').set(emoji);
    } catch (_) {}
  }

  // ── Pin ───────────────────────────────────────────────────────────────────────
  Future<void> _pinMessage(ChatMessage msg) async {
    if (_pins.length >= 3) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max 3 pins. Unpin one first.')));
      return;
    }
    try {
      await _dbRef.child('chats/$_groupId/pins/${msg.id}').set({
        'text': msg.isPoll ? '📊 ${msg.pollQuestion}' : msg.text,
        'senderName': msg.senderName,
        'pinnedAt': DateTime.now().millisecondsSinceEpoch,
        'msgId': msg.id,
      });
    } catch (_) {}
  }

  Future<void> _unpinMessage(String msgId) async {
    try { await _dbRef.child('chats/$_groupId/pins/$msgId').remove(); } catch (_) {}
  }

  bool _isPinned(String msgId) => _pins.any((p) => p['id'] == msgId);

  // ── Edit/Delete ───────────────────────────────────────────────────────────────
  Future<void> _editMessage(ChatMessage msg, String newText) async {
    if (newText.trim().isEmpty) return;
    try { await _dbRef.child('chats/$_groupId/messages/${msg.id}').update({'text': newText.trim(), 'editedText': newText.trim()}); } catch (_) {}
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    try { await _dbRef.child('chats/$_groupId/messages/${msg.id}').update({'isDeleted': true, 'text': 'This message was removed.'}); } catch (_) {}
  }

  // ── Options sheet ─────────────────────────────────────────────────────────────
  void _showOptions(BuildContext context, ChatMessage msg, bool isMe) {
    final canDelete = isMe && DateTime.now().difference(msg.timestamp).inMinutes < 60;
    final pinned = _isPinned(msg.id);
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => _OptionsSheet(
        msg: msg, isMe: isMe, canDelete: canDelete, isPinned: pinned,
        myUid: _myUid, memberCount: _memberCount,
        onReact: (e) { Navigator.pop(context); _toggleReaction(msg, e); },
        onReply: () { Navigator.pop(context); setState(() { _replyTo = msg; _focusNode.requestFocus(); }); },
        onEdit: isMe && !msg.isPoll ? () { Navigator.pop(context); _showEditDialog(context, msg); } : null,
        onDelete: canDelete ? () { Navigator.pop(context); _deleteMessage(msg); } : null,
        onPin: () { Navigator.pop(context); pinned ? _unpinMessage(msg.id) : _pinMessage(msg); },
      ),
    );
  }

  void _showEditDialog(BuildContext context, ChatMessage msg) {
    final ctrl = TextEditingController(text: msg.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit message', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: TextField(controller: ctrl, autofocus: true, maxLines: null, decoration: const InputDecoration(hintText: 'Edit your message...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () { _editMessage(msg, ctrl.text); Navigator.pop(ctx); }, child: const Text('Save')),
        ],
      ),
    );
  }

  // ── Create poll ───────────────────────────────────────────────────────────────
  void _showCreatePoll() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _CreatePollSheet(
        presetPolls: _presetPolls,
        onSend: (q, opts, multi, presetId) {
          Navigator.pop(sheetCtx); // pop the sheet, not the chat screen
          _sendPoll(question: q, options: opts, allowMultiple: multi, presetId: presetId);
        },
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _scrollToMessage(String msgId) {
    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx >= 0) _scrollCtrl.animateTo(idx * 72.0, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (user == null) return const SizedBox.shrink();

    return Container(
      color: _kChatBg,
      child: Column(children: [
        // Pinned banner
        if (_pins.isNotEmpty) _PinnedBanner(pins: _pins, onUnpin: _unpinMessage, onTap: _scrollToMessage),

        // Messages
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
            : _messages.isEmpty
              ? Center(child: Text('No messages yet', style: GoogleFonts.inter(fontSize: 14, color: _kTickSent)))
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final msg = _messages[i];
                    final isMe = msg.senderUid == user.uid;
                    final showDateDivider = i == 0 || !_isSameDay(_messages[i - 1].timestamp, msg.timestamp);
                    final isLast = i == _messages.length - 1;
                    final nextMsg = isLast ? null : _messages[i + 1];
                    final showTime = isLast || nextMsg!.senderUid != msg.senderUid || !_isSameMinute(msg.timestamp, nextMsg.timestamp);
                    final showAvatar = !isMe && (isLast || nextMsg!.senderUid != msg.senderUid);
                    final isFirstUnread = _firstUnreadIndex != null && i == _firstUnreadIndex;
                    return Column(children: [
                      if (isFirstUnread) _UnreadDivider(),
                      if (showDateDivider) _DateDivider(date: msg.timestamp),
                      _MessageBubble(
                        message: msg, isMe: isMe, showTime: showTime,
                        showAvatar: showAvatar, myUid: user.uid, memberCount: _memberCount,
                        onLongPress: !msg.isDeleted ? () => _showOptions(context, msg, isMe) : null,
                        onReply: () => setState(() { _replyTo = msg; _focusNode.requestFocus(); }),
                        onReact: (e) => _toggleReaction(msg, e),
                        onVote: (idx) => _vote(msg, idx),
                      ),
                    ]);
                  },
                ),
        ),

        // Link preview card (above input)
        if (_linkPreview != null) _LinkPreviewBar(preview: _linkPreview!, onDismiss: () => setState(() { _linkPreview = null; _lastCheckedUrl = null; })),

        // Reply bar
        if (_replyTo != null)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            color: const Color(0xFF1F2C34),
            child: Row(children: [
              Container(width: 3, height: 36, color: _kWaGreen, margin: const EdgeInsets.only(right: 10)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_replyTo!.senderName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _kWaGreen)),
                Text(_replyTo!.isDeleted ? 'Removed message' : (_replyTo!.isPoll ? '📊 ${_replyTo!.pollQuestion}' : _replyTo!.text),
                  style: GoogleFonts.inter(fontSize: 12, color: _kTickSent), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: _kTickSent), onPressed: () => setState(() => _replyTo = null), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]),
          ),

        // Input bar
        _ChatInput(controller: _msgCtrl, focusNode: _focusNode, sending: _sending, onSend: _sendMessage, onPoll: _showCreatePoll),
      ]),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isSameMinute(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day && a.hour == b.hour && a.minute == b.minute;
}

// ─── Link Preview Bar (above input) ──────────────────────────────────────────
class _LinkPreviewBar extends StatelessWidget {
  final Map<String, String> preview;
  final VoidCallback onDismiss;
  const _LinkPreviewBar({required this.preview, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1F2C34),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(children: [
        Container(width: 3, height: 50, color: _kWaGreen, margin: const EdgeInsets.only(right: 10)),
        if ((preview['image'] ?? '').isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(preview['image']!, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((preview['title'] ?? '').isNotEmpty)
            Text(preview['title']!, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _kWaGreen), maxLines: 1, overflow: TextOverflow.ellipsis),
          if ((preview['description'] ?? '').isNotEmpty)
            Text(preview['description']!, style: GoogleFonts.inter(fontSize: 11, color: _kTickSent), maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(preview['url'] ?? '', style: GoogleFonts.inter(fontSize: 10, color: _kTickSent), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: _kTickSent), onPressed: onDismiss, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
    );
  }
}

// ─── Create Poll Sheet ────────────────────────────────────────────────────────
class _CreatePollSheet extends StatefulWidget {
  final List<Map<String, dynamic>> presetPolls;
  final void Function(String, List<String>, bool, String?) onSend;
  const _CreatePollSheet({required this.presetPolls, required this.onSend});
  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [TextEditingController(), TextEditingController()];
  bool _allowMultiple = false;
  String? _error;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) c.dispose();
    super.dispose();
  }

  void _loadPreset(Map<String, dynamic> preset) {
    _questionCtrl.text = preset['question'] ?? '';
    final opts = List<String>.from(preset['options'] ?? []);
    while (_optionCtrls.length < opts.length) _optionCtrls.add(TextEditingController());
    for (int i = 0; i < _optionCtrls.length; i++) {
      _optionCtrls[i].text = i < opts.length ? opts[i] : '';
    }
    _allowMultiple = preset['allowMultiple'] ?? false;
    setState(() {});
  }

  void _submit() {
    final q = _questionCtrl.text.trim();
    if (q.isEmpty) { setState(() => _error = 'Enter a question.'); return; }
    final opts = _optionCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (opts.length < 2) { setState(() => _error = 'Add at least 2 options.'); return; }
    setState(() => _error = null);
    widget.onSend(q, opts, _allowMultiple, null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(color: Color(0xFF1F2C34), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: _kTickSent.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Create Poll', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          if (widget.presetPolls.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.bookmark_outline_rounded, size: 16, color: _kWaGreen),
              label: Text('Preset', style: GoogleFonts.inter(fontSize: 13, color: _kWaGreen)),
              onPressed: () => _showPresetPicker(),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
        ]),
        const SizedBox(height: 14),

        // Question
        Text('Question', style: GoogleFonts.inter(fontSize: 12, color: _kTickSent, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _questionCtrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecor('Ask a question...'),
        ),
        const SizedBox(height: 14),

        // Options
        Text('Options (min 2, max 10)', style: GoogleFonts.inter(fontSize: 12, color: _kTickSent, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...List.generate(_optionCtrls.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _optionCtrls[i],
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecor('Option ${i + 1}'),
            )),
            if (i >= 2) IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, color: _kTickSent, size: 20),
              onPressed: () => setState(() { _optionCtrls[i].dispose(); _optionCtrls.removeAt(i); }),
              padding: EdgeInsets.zero,
            ),
          ]),
        )),
        if (_optionCtrls.length < 10)
          TextButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18, color: _kWaGreen),
            label: Text('Add option', style: GoogleFonts.inter(fontSize: 13, color: _kWaGreen)),
            onPressed: () => setState(() => _optionCtrls.add(TextEditingController())),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        const SizedBox(height: 8),

        // Allow multiple
        Row(children: [
          Switch(value: _allowMultiple, onChanged: (v) => setState(() => _allowMultiple = v), activeColor: _kWaGreen),
          Text('Allow multiple answers', style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
        ]),

        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.error)),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(backgroundColor: _kWaGreen, foregroundColor: Colors.white),
            child: Text('Send Poll', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ),
      ])),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(color: _kTickSent),
    filled: true, fillColor: const Color(0xFF2A3C47),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  );

  void _showPresetPicker() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Color(0xFF1F2C34), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Preset Polls', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          ...widget.presetPolls.map((p) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.poll_outlined, color: _kWaGreen),
            title: Text(p['question'] ?? '', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
            subtitle: Text('${(p['options'] as List?)?.length ?? 0} options', style: GoogleFonts.inter(fontSize: 12, color: _kTickSent)),
            onTap: () { Navigator.pop(context); _loadPreset(p); },
          )),
        ]),
      ),
    );
  }
}

// ─── Poll Bubble ──────────────────────────────────────────────────────────────
class _PollBubble extends StatelessWidget {
  final ChatMessage msg;
  final String myUid;
  final void Function(int) onVote;

  const _PollBubble({required this.msg, required this.myUid, required this.onVote});

  @override
  Widget build(BuildContext context) {
    final myVotes = List<int>.from(msg.pollVotes[myUid] ?? []);
    final hasVoted = myVotes.isNotEmpty;
    final totalVotes = msg.pollVotes.values.fold(0, (acc, v) => acc + (v as List).length);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.poll_rounded, size: 14, color: _kTickSent),
        const SizedBox(width: 6),
        Text('POLL', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: _kTickSent)),
      ]),
      const SizedBox(height: 6),
      Text(msg.pollQuestion ?? '', style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3)),
      if (msg.pollAllowMultiple)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Multiple answers allowed', style: GoogleFonts.inter(fontSize: 10, color: _kTickSent)),
        ),
      const SizedBox(height: 10),
      ...msg.pollOptions.asMap().entries.map((entry) {
        final i = entry.key;
        final opt = entry.value;
        final voteCount = msg.pollVotes.values.where((v) => (v as List).contains(i)).length;
        final pct = totalVotes > 0 ? voteCount / totalVotes : 0.0;
        final isSelected = myVotes.contains(i);

        return GestureDetector(
          onTap: () => onVote(i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Stack(children: [
              // Background progress bar
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3C47),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSelected ? _kWaGreen : Colors.transparent, width: 1.5),
                ),
              ),
              // Fill
              if (hasVoted)
                Positioned.fill(
                  child: FractionallySizedBox(
                    widthFactor: pct,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? _kWaGreen.withOpacity(0.3) : const Color(0xFF3D5260),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              // Text row
              SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    if (isSelected) const Icon(Icons.check_circle_rounded, size: 16, color: _kWaGreen),
                    if (!isSelected) Icon(msg.pollAllowMultiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_unchecked_rounded, size: 16, color: _kTickSent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(opt, style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white))),
                    if (hasVoted) Text('$voteCount', style: GoogleFonts.inter(fontSize: 12, color: _kTickSent, fontWeight: FontWeight.w600)),
                    if (hasVoted) ...[
                      const SizedBox(width: 4),
                      Text('${(pct * 100).round()}%', style: GoogleFonts.inter(fontSize: 11, color: _kTickSent)),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        );
      }),
      Text('$totalVotes vote${totalVotes == 1 ? '' : 's'}', style: GoogleFonts.inter(fontSize: 11, color: _kTickSent)),
    ]);
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────
class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showTime;
  final bool showAvatar;
  final String myUid;
  final int memberCount;
  final VoidCallback? onLongPress;
  final VoidCallback onReply;
  final void Function(String) onReact;
  final void Function(int) onVote;

  const _MessageBubble({
    required this.message, required this.isMe, required this.showTime,
    required this.showAvatar, required this.myUid, required this.memberCount,
    required this.onReply, required this.onReact, required this.onVote,
    this.onLongPress,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  double _dragX = 0;
  bool _triggered = false;

  void _showWhoReacted(BuildContext context, Map<String, String> reactions) {
    final Map<String, List<String>> byEmoji = {};
    for (final e in reactions.entries) {
      byEmoji.putIfAbsent(e.value, () => []).add(e.key);
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1F2C34),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: _kTickSent.withOpacity(0.4), borderRadius: BorderRadius.circular(2)))),
          Text('Reactions', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          ...byEmoji.entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Text(entry.key, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(child: Text(
                '${entry.value.length} ${entry.value.length == 1 ? "person" : "people"}',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
              )),
              GestureDetector(
                onTap: () { Navigator.pop(context); widget.onReact(entry.key); },
                child: Text('Toggle mine', style: GoogleFonts.inter(fontSize: 12, color: _kWaGreen)),
              ),
            ]),
          )),
        ]),
      ),
    );
  }

  void _openProfile(BuildContext context) {
    FirebaseFirestore.instance.collection('users').doc(widget.message.senderUid).get().then((doc) {
      if (doc.exists && context.mounted) {
        final user = UserModel.fromMap(doc.data() as Map<String, dynamic>);
        Navigator.push(context, MaterialPageRoute(builder: (_) => MemberProfileScreen(member: user)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    if (msg.isPreset) return _PresetMessageBubble(message: msg);

    final timeStr = DateFormat('HH:mm').format(msg.timestamp);
    final bubbleColor = msg.isDeleted ? const Color(0xFF182229) : widget.isMe ? _kMyBubble : _kTheirBubble;
    final isBigEmoji = !msg.isDeleted && !msg.isPoll && _isSingleEmoji(msg.text) && msg.replyToText == null;

    Widget? ticks;
    if (widget.isMe && !msg.isDeleted) {
      final seenCount = msg.seenBy.where((u) => u != widget.myUid).length;
      final allSeen = seenCount >= widget.memberCount - 1 && widget.memberCount > 1;
      ticks = Icon(Icons.done_all_rounded, size: 14, color: allSeen ? _kTickSeen : _kTickSent);
    }

    final Map<String, int> reactionCounts = {};
    for (final e in msg.reactions.values) reactionCounts[e] = (reactionCounts[e] ?? 0) + 1;
    final myReaction = msg.reactions[widget.myUid];

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onHorizontalDragUpdate: (d) {
          final dx = d.delta.dx;
          // isMe: swipe LEFT (negative); others: swipe RIGHT (positive)
          final isCorrectDir = widget.isMe ? dx < 0 : dx > 0;
          if (isCorrectDir) {
            setState(() { _dragX = (_dragX + dx.abs()).clamp(0.0, 64.0); });
          } else if (_dragX > 0) {
            // Swipe opposite direction → cancel
            setState(() { _dragX = (_dragX - dx.abs() * 1.5).clamp(0.0, 64.0); });
          }
        },
        onHorizontalDragEnd: (d) {
          if (_dragX > 40 && !_triggered) {
            _triggered = true;
            HapticFeedback.mediumImpact();
            widget.onReply();
          }
          setState(() { _dragX = 0; _triggered = false; });
        },
        child: Transform.translate(
          offset: Offset(widget.isMe ? -_dragX : _dragX, 0),
          child: Row(
            mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar
              if (!widget.isMe)
                widget.showAvatar
                  ? GestureDetector(
                      onTap: () => _openProfile(context),
                      child: Container(
                        width: 32, height: 32, margin: const EdgeInsets.only(right: 6, bottom: 2),
                        decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), shape: BoxShape.circle),
                        child: Center(child: Text(
                          msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                        )),
                      ),
                    )
                  : const SizedBox(width: 38),

              Flexible(
                child: Column(
                  crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPress: widget.onLongPress,
                      child: isBigEmoji
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            child: IntrinsicWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(msg.text, style: const TextStyle(fontSize: 44, height: 1.1)),
                              if (widget.showTime) Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                                Text(DateFormat('HH:mm').format(msg.timestamp), style: GoogleFonts.inter(fontSize: 10, color: _kTickSent)),
                                if (widget.isMe) ...[const SizedBox(width: 3), Icon(Icons.done_all_rounded, size: 14, color: msg.seenBy.where((u) => u != widget.myUid).isNotEmpty ? _kTickSeen : _kTickSent)],
                              ]),
                            ])),
                          )
                        : Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(widget.isMe ? 12 : 2),
                            bottomRight: Radius.circular(widget.isMe ? 2 : 12),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: IntrinsicWidth(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../models/user_model.dart';
import '../widgets/common_widgets.dart';
import 'member_profile_screen.dart';

// ── WhatsApp-style colors ──────────────────────────────────────────────────────
const _kMyBubble     = Color(0xFF005C4B);
const _kTheirBubble  = Color(0xFF1F2C34);
const _kChatBg       = Color(0xFF0B141A);
const _kReplyMyBg    = Color(0xFF025144);
const _kReplyTheirBg = Color(0xFF182229);
const _kTickSent     = Color(0xFF8696A0);
const _kTickSeen     = Color(0xFF53BDEB);
const _kWaGreen      = Color(0xFF00A884);

// Single emoji check (no ASCII letters/digits, non-ASCII chars present)
bool _isSingleEmoji(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 8) return false;
  if (RegExp(r'[a-zA-Z0-9 ]').hasMatch(t)) return false;
  return t.runes.any((r) => r > 127);
}

const _kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];


class _InlineLinkPreview extends StatelessWidget {
  final Map<String, String> preview;
  const _InlineLinkPreview({required this.preview});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final url = preview['url'] ?? '';
        if (url.isEmpty) return;
        final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
        if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(color: const Color(0xFF182229), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: _kWaGreen, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((preview['image'] ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(topRight: Radius.circular(8)),
              child: Image.network(preview['image']!, height: 120, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((preview['title'] ?? '').isNotEmpty)
                Text(preview['title']!, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
              if ((preview['description'] ?? '').isNotEmpty)
                Text(preview['description']!, style: GoogleFonts.inter(fontSize: 11, color: _kTickSent), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(Uri.tryParse(preview['url'] ?? '')?.host ?? '', style: GoogleFonts.inter(fontSize: 10, color: _kWaGreen)),
            ]),
          ),
        ]),
      ),
    );
  }
}


// ─── Unread Divider ────────────────────────────────────────────────────────────
class _UnreadDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        const Expanded(child: Divider(color: Color(0xFF53BDEB), thickness: 1)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2C35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF53BDEB), width: 1),
          ),
          child: Text('Unread messages',
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF53BDEB), fontWeight: FontWeight.w600)),
        ),
        const Expanded(child: Divider(color: Color(0xFF53BDEB), thickness: 1)),
      ]),
    );
  }
}
