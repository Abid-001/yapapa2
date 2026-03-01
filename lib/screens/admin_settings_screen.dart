import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
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
                    value: '${group.memberUids.length} / 10',
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
