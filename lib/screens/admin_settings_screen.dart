import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../widgets/common_widgets.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<UserModel> _members = [];
  bool _loadingMembers = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final auth = context.read<AuthService>();
    final group = auth.currentGroup;
    if (group == null) return;

    try {
      final docs = await Future.wait(
        group.memberUids
            .map((uid) => _db.collection('users').doc(uid).get()),
      );
      final members = docs
          .where((d) => d.exists)
          .map((d) => UserModel.fromMap(d.data()!))
          .toList()
        ..sort((a, b) {
          if (a.isAdmin) return -1;
          if (b.isAdmin) return 1;
          return a.username.compareTo(b.username);
        });
      if (mounted) {
        setState(() {
          _members = members;
          _loadingMembers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  void _showTransferDialog(UserModel newAdmin) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Transfer Admin?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Transfer admin role to ${newAdmin.username}? You will lose admin privileges.',
          style: GoogleFonts.inter(
              fontSize: 14, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await context
                  .read<AuthService>()
                  .transferAdmin(newAdmin.uid);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${newAdmin.username} is now the admin.'),
                  ),
                );
                Navigator.pop(context); // close settings
              }
            },
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog(UserModel member) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Remove Member?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove ${member.username} from the group? They will need to rejoin with the invite code.',
          style: GoogleFonts.inter(
              fontSize: 14, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error),
            onPressed: () async {
              Navigator.pop(context);
              final err = await context
                  .read<AuthService>()
                  .removeMember(member.uid);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(err ??
                        '${member.username} has been removed.'),
                  ),
                );
              }
            },
            child: const Text('Remove',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final group = auth.currentGroup;
    if (user == null || group == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.inter(
              fontSize: 18, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Invite code ───────────────────────────────────────────────
            _SectionTitle('Group Info'),
            const SizedBox(height: 10),
            GradientCard(
              child: Column(
                children: [
                  _InfoRow(
                    label: 'Invite Code',
                    value: group.inviteCode,
                    trailing: IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          size: 18, color: AppTheme.textSecondary),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: group.inviteCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Invite code copied!')),
                        );
                      },
                    ),
                  ),
                  const Divider(color: AppTheme.divider, height: 1),
                  _InfoRow(
                    label: 'Members',
                    value: '${group.memberUids.length} / 20',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Expense Types (Admin only) ────────────────────────────────
            if (user.isAdmin) ...[
              _SectionTitle('Expense Types'),
              const SizedBox(height: 4),
              Text(
                'These are the TYPE categories members must assign to their expenses.',
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              _ExpenseTypesEditor(
                types: group.expenseTypes,
                onSave: (types) async {
                  await auth.updateExpenseTypes(types);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Expense types updated!')),
                    );
                  }
                },
              ),
              const SizedBox(height: 24),

              // ── Default Screentime Limit ────────────────────────────────
              _SectionTitle('Default Daily Screentime Limit'),
              const SizedBox(height: 4),
              Text(
                'Applied to members who have not set their own limit.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              GradientCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          group.defaultScreentimeMinutes > 0
                              ? '${(group.defaultScreentimeMinutes / 60).toStringAsFixed(1)} hours / day'
                              : 'Not set',
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => _showDefaultLimitDialog(context, auth, group.defaultScreentimeMinutes),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: GoogleFonts.inter(fontSize: 12),
                        ),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Preset Polls ──────────────────────────────────────────────
              _SectionTitle('Preset Polls'),
              const SizedBox(height: 4),
              Text(
                'Members can use these pre-made polls in chat.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              _PresetPollsEditor(groupId: group.groupId),
              const SizedBox(height: 24),

              // ── Monthly Reminders ─────────────────────────────────────────
              _SectionTitle('Monthly Reminders'),
              const SizedBox(height: 4),
              Text(
                'Show reminder banners on the home screen during a date window each month. Max 3 reminders.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              _RemindersEditor(
                reminders: group.monthlyReminders,
                onSave: (reminders) async {
                  await auth.updateMonthlyReminders(reminders);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminders updated!')));
                },
              ),

            ],

            // ── Members list ──────────────────────────────────────────────
            _SectionTitle('Members'),
            const SizedBox(height: 10),
            _loadingMembers
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 2),
                    ),
                  )
                : GradientCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: _members.asMap().entries.map((entry) {
                        final i = entry.key;
                        final member = entry.value;
                        final isLast = i == _members.length - 1;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: member.isAdmin
                                          ? AppTheme.primary
                                              .withOpacity(0.2)
                                          : AppTheme.surfaceHighlight,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        member.username.isNotEmpty
                                            ? member.username[0]
                                                .toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: member.isAdmin
                                              ? AppTheme.primary
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          member.username,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        if (member.isAdmin)
                                          Text(
                                            'Admin',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppTheme.primary,
                                              fontWeight:
                                                  FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Transfer admin button
                                  if (user.isAdmin &&
                                      !member.isAdmin &&
                                      member.uid != user.uid)
                                    TextButton(
                                      onPressed: () =>
                                          _showTransferDialog(member),
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            AppTheme.accentOrange,
                                        textStyle: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w600),
                                        padding: const EdgeInsets
                                            .symmetric(horizontal: 10),
                                      ),
                                      child:
                                          const Text('Make Admin'),
                                    ),
                                  // Remove member button
                                  if (user.isAdmin &&
                                      member.uid != user.uid)
                                    IconButton(
                                      icon: const Icon(
                                          Icons.person_remove_rounded,
                                          size: 18,
                                          color: AppTheme.error),
                                      tooltip: 'Remove member',
                                      onPressed: () =>
                                          _showRemoveDialog(member),
                                    ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              const Divider(
                                  color: AppTheme.divider,
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
            const SizedBox(height: 24),

            // ── Account actions ───────────────────────────────────────────
            _SectionTitle('Account'),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded,
                    color: AppTheme.error, size: 18),
                label: const Text('Log Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(
                      color: AppTheme.error, width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDefaultLimitDialog(BuildContext context, AuthService auth, int currentMinutes) {
    int hours = currentMinutes ~/ 60;
    int minutes = currentMinutes % 60;
    final ctrl = TextEditingController(text: (currentMinutes / 60).toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Set Default Limit',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter hours (e.g. 3.0 = 3 hours, 1.5 = 90 min)',
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  hintText: '3.0', suffixText: 'hours'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                await auth.updateDefaultScreentime((val * 60).round());
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Default limit updated!')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showNukeDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('☢️ Nuke Server Data',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w700, color: AppTheme.error)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This will DELETE ALL groups, users, expenses, screentime, chat messages and PINs from the server permanently. Cannot be undone.\n\nType NUKE to confirm:',
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(hintText: 'Type NUKE'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error),
            onPressed: () async {
              if (ctrl.text.trim() != 'NUKE') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Type NUKE exactly to confirm.')),
                );
                return;
              }
              Navigator.pop(context);
              _nukeServer(context);
            },
            child: const Text('DELETE EVERYTHING',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _nukeServer(BuildContext context) async {
    final db = FirebaseFirestore.instance;
    try {
      // Delete all top-level collections
      for (final col in ['groups', 'users', 'pins', 'userLimits']) {
        final docs = await db.collection(col).get();
        for (final doc in docs.docs) {
          // Delete subcollections for groups
          if (col == 'groups') {
            for (final sub in ['expenses', 'screentime', 'presets', 'pokes', 'notifications']) {
              final subs = await doc.reference.collection(sub).get();
              for (final s in subs.docs) {
                await s.reference.delete();
              }
            }
          }
          await doc.reference.delete();
        }
      }
      if (context.mounted) {
        await context.read<AuthService>().logout();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during nuke: $e')),
        );
      }
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Log Out?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          'You will need your username, PIN and invite code to log back in.',
          style: GoogleFonts.inter(
              fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<AuthService>().logout();
            },
            child: const Text('Log Out',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

// ─── Expense Types Editor ─────────────────────────────────────────────────────
class _ExpenseTypesEditor extends StatefulWidget {
  final List<String> types;
  final void Function(List<String>) onSave;

  const _ExpenseTypesEditor(
      {required this.types, required this.onSave});

  @override
  State<_ExpenseTypesEditor> createState() =>
      _ExpenseTypesEditorState();
}

class _ExpenseTypesEditorState extends State<_ExpenseTypesEditor> {
  late List<String> _types;
  final _addCtrl = TextEditingController();
  bool _adding = false;
  String? _addError;

  @override
  void initState() {
    super.initState();
    _types = List.from(widget.types);
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  void _addType() {
    final t = _addCtrl.text.trim();
    if (t.isEmpty) {
      setState(() => _addError = 'Enter a type name.');
      return;
    }
    if (t.length > 20) {
      setState(() => _addError = 'Max 20 characters.');
      return;
    }
    if (_types.map((x) => x.toLowerCase()).contains(t.toLowerCase())) {
      setState(() => _addError = 'Type already exists.');
      return;
    }
    setState(() {
      _types.add(t);
      _adding = false;
      _addError = null;
    });
    _addCtrl.clear();
    widget.onSave(_types);
  }

  void _removeType(String type) {
    setState(() => _types.remove(type));
    widget.onSave(_types);
  }

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._types.map((type) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          type,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _removeType(type),
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: AppTheme.primary),
                        ),
                      ],
                    ),
                  )),
              GestureDetector(
                onTap: () =>
                    setState(() => _adding = !_adding),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHighlight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.divider, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _adding
                            ? Icons.close_rounded
                            : Icons.add_rounded,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _adding ? 'Cancel' : 'Add Type',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_adding) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. Entertainment',
                      errorText: _addError,
                    ),
                    textCapitalization: TextCapitalization.words,
                    maxLength: 20,
                    onSubmitted: (_) => _addType(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _addType,
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
        ],
      ),
    );
  }
}

// ─── Tiny helpers ─────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppTheme.textHint,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow(
      {required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    letterSpacing: label == 'Invite Code' ? 3 : 0,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─── Preset Polls Editor ──────────────────────────────────────────────────────
class _PresetPollsEditor extends StatefulWidget {
  final String groupId;
  const _PresetPollsEditor({required this.groupId});
  @override
  State<_PresetPollsEditor> createState() => _PresetPollsEditorState();
}

class _PresetPollsEditorState extends State<_PresetPollsEditor> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _polls = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final snap = await _db.collection('groups').doc(widget.groupId).collection('presetPolls').get();
      if (mounted) setState(() {
        _polls = snap.docs.map((d) { final m = d.data(); m['id'] = d.id; return m; }).toList();
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _delete(String id) async {
    await _db.collection('groups').doc(widget.groupId).collection('presetPolls').doc(id).delete();
    setState(() => _polls.removeWhere((p) => p['id'] == id));
  }

  void _showEditDialog([Map<String, dynamic>? existing]) {
    final qCtrl = TextEditingController(text: existing?['question'] ?? '');
    final opts = existing != null ? List<TextEditingController>.from(
      (existing['options'] as List).map((o) => TextEditingController(text: o.toString()))
    ) : [TextEditingController(), TextEditingController()];
    bool multi = existing?['allowMultiple'] ?? false;
    String? err;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        title: Text(existing != null ? 'Edit Preset Poll' : 'Add Preset Poll', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: qCtrl, decoration: const InputDecoration(hintText: 'Poll question'), maxLength: 100),
          const SizedBox(height: 12),
          ...List.generate(opts.length, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: TextField(controller: opts[i], decoration: InputDecoration(hintText: 'Option ${i + 1}'))),
              if (i >= 2) IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppTheme.error),
                onPressed: () { ss(() { opts[i].dispose(); opts.removeAt(i); }); },
                padding: EdgeInsets.zero,
              ),
            ]),
          )),
          if (opts.length < 10)
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add option'),
              onPressed: () => ss(() => opts.add(TextEditingController())),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          Row(children: [
            Switch(value: multi, onChanged: (v) => ss(() => multi = v), activeColor: AppTheme.primary),
            const Text('Allow multiple answers'),
          ]),
          if (err != null) Text(err!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final q = qCtrl.text.trim();
              final options = opts.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
              if (q.isEmpty) { ss(() => err = 'Enter a question.'); return; }
              if (options.length < 2) { ss(() => err = 'Add at least 2 options.'); return; }
              final data = {'question': q, 'options': options, 'allowMultiple': multi};
              if (existing != null) {
                await _db.collection('groups').doc(widget.groupId).collection('presetPolls').doc(existing['id']).update(data);
              } else {
                await _db.collection('groups').doc(widget.groupId).collection('presetPolls').add(data);
              }
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Save'),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2));
    return GradientCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_polls.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('No preset polls yet.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textHint)),
          ),
        ..._polls.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            const Icon(Icons.poll_outlined, size: 18, color: AppTheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['question'] ?? '', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              Text('${(p['options'] as List?)?.length ?? 0} options${p['allowMultiple'] == true ? ' · multiple' : ''}',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
            ])),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.textSecondary), onPressed: () => _showEditDialog(p), padding: EdgeInsets.zero),
            IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error), onPressed: () => _delete(p['id']), padding: EdgeInsets.zero),
          ]),
        )),
        TextButton.icon(
          onPressed: () => _showEditDialog(),
          icon: const Icon(Icons.add_rounded, size: 16, color: AppTheme.primary),
          label: Text('Add Preset Poll', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.primary)),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ]),
    );
  }
}

// ─── Monthly Reminders Editor ─────────────────────────────────────────────────
class _RemindersEditor extends StatefulWidget {
  final List<MonthlyReminder> reminders;
  final void Function(List<MonthlyReminder>) onSave;
  const _RemindersEditor({required this.reminders, required this.onSave});
  @override
  State<_RemindersEditor> createState() => _RemindersEditorState();
}

class _RemindersEditorState extends State<_RemindersEditor> {
  late List<MonthlyReminder> _reminders;

  @override
  void initState() { super.initState(); _reminders = List.from(widget.reminders); }

  void _showEditDialog([MonthlyReminder? existing, int? idx]) {
    final textCtrl = TextEditingController(text: existing?.text ?? '');
    int startDay = existing?.startDay ?? 1;
    int endDay = existing?.endDay ?? 10;
    String? err;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        title: Text(existing != null ? 'Edit Reminder' : 'Add Reminder', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: textCtrl, maxLines: 3, maxLength: 200,
            decoration: const InputDecoration(hintText: 'Reminder message shown on home screen...')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Column(children: [
              Text('From day', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              DropdownButton<int>(
                value: startDay,
                isExpanded: true,
                items: List.generate(28, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                onChanged: (v) => ss(() => startDay = v ?? 1),
              ),
            ])),
            const SizedBox(width: 16),
            Expanded(child: Column(children: [
              Text('To day', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              DropdownButton<int>(
                value: endDay,
                isExpanded: true,
                items: List.generate(28, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                onChanged: (v) => ss(() => endDay = v ?? 10),
              ),
            ])),
          ]),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: AppTheme.error, fontSize: 12))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final t = textCtrl.text.trim();
              if (t.isEmpty) { ss(() => err = 'Enter reminder text.'); return; }
              if (endDay < startDay) { ss(() => err = 'End day must be ≥ start day.'); return; }
              final r = MonthlyReminder(text: t, startDay: startDay, endDay: endDay);
              setState(() {
                if (idx != null) _reminders[idx] = r;
                else _reminders.add(r);
              });
              widget.onSave(_reminders);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      )),
    );
  }

  void _delete(int idx) {
    setState(() => _reminders.removeAt(idx));
    widget.onSave(_reminders);
  }

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_reminders.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('No reminders set.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textHint)),
          ),
        ..._reminders.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.notifications_active_rounded, size: 18, color: AppTheme.accentOrange),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value.text, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('Day ${e.value.startDay} – ${e.value.endDay} every month',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
            ])),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.textSecondary), onPressed: () => _showEditDialog(e.value, e.key), padding: EdgeInsets.zero),
            IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error), onPressed: () => _delete(e.key), padding: EdgeInsets.zero),
          ]),
        )),
        if (_reminders.length < 3)
          TextButton.icon(
            onPressed: () => _showEditDialog(),
            icon: const Icon(Icons.add_rounded, size: 16, color: AppTheme.accentOrange),
            label: Text('Add Reminder', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.accentOrange)),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        if (_reminders.length >= 3)
          Text('Max 3 reminders reached.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textHint)),
      ]),
    );
  }
}
