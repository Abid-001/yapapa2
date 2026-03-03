import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../widgets/common_widgets.dart';
import 'preset_notification_sheet.dart';
import 'budget_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onGoToChat;
  final VoidCallback? onGoToBudget;
  final VoidCallback? onGoToScreentime;
  final VoidCallback? onGoToLeaderboard;
  const HomeScreen({super.key, this.onGoToChat, this.onGoToBudget, this.onGoToScreentime, this.onGoToLeaderboard});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BudgetService _budgetService = BudgetService();

  @override
  void initState() { super.initState(); _runCleanup(); }

  Future<void> _runCleanup() async {
    final auth = context.read<AuthService>();
    final groupId = auth.currentGroup?.groupId;
    if (groupId != null) await _budgetService.cleanupOldExpenses(groupId);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final group = auth.currentGroup;
    if (user == null || group == null) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceElevated,
      onRefresh: () async { await auth.refreshGroup(); setState(() {}); },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _WelcomeRow(username: user.username, isAdmin: user.isAdmin),
          const SizedBox(height: 12),

          // ── Group reminder banners (admin-set) ─────────────────────
          ..._activeReminders(group.monthlyReminders).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReminderBanner(text: r.text, isPersonal: false),
          )),
          // ── Personal reminder banners (user-set) ──────────────────────
          ..._activePersonalReminders(user.personalReminders).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReminderBanner(text: r.text, isPersonal: true),
          )),

          const SizedBox(height: 8),


          // ── Clickable stat cards ────────────────────────────────────────
          StreamBuilder<List<ExpenseModel>>(
            stream: _budgetService.getMyMonthlyExpenses(groupId: group.groupId, uid: user.uid, month: DateTime.now()),
            builder: (context, snapshot) {
              final expenses = snapshot.data ?? [];
              final total = BudgetService.totalFromList(expenses);
              return Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => widget.onGoToBudget?.call(),
                  child: StatCard(label: 'This Month', value: '৳${total.toStringAsFixed(0)}', icon: Icons.account_balance_wallet_rounded, iconColor: AppTheme.accent),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: () => widget.onGoToScreentime?.call(),
                  child: const StatCard(label: "Today's Screentime", value: '--', icon: Icons.phone_android_rounded, iconColor: AppTheme.accentOrange),
                )),
              ]);
            },
          ),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: () => widget.onGoToLeaderboard?.call(),
            child: _RankCard(groupId: group.groupId, uid: user.uid, memberUids: group.memberUids),
          ),
          const SizedBox(height: 20),

          SectionHeader(title: 'Quick Notification'),
          const SizedBox(height: 12),
          _QuickPresetButton(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const AddExpenseSheet(),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Expense'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),

          SectionHeader(title: 'Recent Notifications'),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => widget.onGoToChat?.call(),
            child: _RecentNotificationsPreview(groupId: group.groupId),
          ),
          const SizedBox(height: 20),
          _PersonalRemindersSection(user: user),
        ]),
      ),
    );
  }
}

// ── Reminder helpers ──────────────────────────────────────────────────────────
List<MonthlyReminder> _activeReminders(List<MonthlyReminder> all) {
  final today = DateTime.now().day;
  return all.where((r) => today >= r.startDay && today <= r.endDay).toList();
}

List<PersonalReminder> _activePersonalReminders(List<PersonalReminder> all) {
  final today = DateTime.now().day;
  return all.where((r) => today >= r.startDay && today <= r.endDay).toList();
}

// ── Reminder Banner ───────────────────────────────────────────────────────────
class _ReminderBanner extends StatelessWidget {
  final String text;
  final bool isPersonal;
  const _ReminderBanner({required this.text, this.isPersonal = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPersonal
            ? [AppTheme.primary.withOpacity(0.18), AppTheme.primaryLight.withOpacity(0.10)]
            : [AppTheme.accentOrange.withOpacity(0.18), AppTheme.accentYellow.withOpacity(0.10)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentOrange.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.notifications_active_rounded, size: 18, color: AppTheme.accentOrange),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Welcome Row ───────────────────────────────────────────────────────────────
class _WelcomeRow extends StatelessWidget {
  final String username; final bool isAdmin;
  const _WelcomeRow({required this.username, required this.isAdmin});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 44, height: 44, decoration: BoxDecoration(gradient: AppTheme.primaryGradient, shape: BoxShape.circle),
        child: Center(child: Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hey, $username 👋', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary), overflow: TextOverflow.ellipsis),
        if (isAdmin) Container(margin: const EdgeInsets.only(top: 2), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
          child: Text('Admin', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary))),
      ])),
    ]);
  }
}

// ── Invite Code Card ──────────────────────────────────────────────────────────
class _InviteCodeCard extends StatelessWidget {
  final String code;
  const _InviteCodeCard({required this.code});
  @override
  Widget build(BuildContext context) {
    return GradientCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      colors: [AppTheme.primary.withOpacity(0.15), AppTheme.surfaceElevated],
      child: Row(children: [
        const Icon(Icons.group_outlined, color: AppTheme.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Group Invite Code', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 2),
          Text(code, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: 4)),
        ])),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.textSecondary),
          onPressed: () {
            // Fix: actually copy to clipboard
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied!'), duration: Duration(seconds: 2)));
          },
          tooltip: 'Copy code', padding: EdgeInsets.zero, constraints: const BoxConstraints(),
        ),
      ]),
    );
  }
}

// ── Rank Card ─────────────────────────────────────────────────────────────────
class _RankCard extends StatefulWidget {
  final String groupId, uid; final List<String> memberUids;
  const _RankCard({required this.groupId, required this.uid, required this.memberUids});
  @override
  State<_RankCard> createState() => _RankCardState();
}
class _RankCardState extends State<_RankCard> {
  final BudgetService _budgetService = BudgetService();
  int? _rank; int _total = 0;
  @override
  void initState() { super.initState(); _loadRank(); }
  Future<void> _loadRank() async {
    try {
      final totals = await _budgetService.getAllMembersMonthlyTotal(groupId: widget.groupId, memberUids: widget.memberUids, month: DateTime.now());
      final sorted = totals.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      final rank = sorted.indexWhere((e) => e.key == widget.uid) + 1;
      if (mounted) setState(() { _rank = rank > 0 ? rank : null; _total = widget.memberUids.length; });
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    return GradientCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        if (_rank != null) RankBadge(rank: _rank!) else const Icon(Icons.leaderboard_rounded, color: AppTheme.primary, size: 26),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your Rank This Month', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 3),
          Text(_rank != null ? '#$_rank out of $_total' : 'No data yet', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        ])),
        Text('(expenses)', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textHint)),
      ]),
    );
  }
}

// ── Quick Preset Button ───────────────────────────────────────────────────────
class _QuickPresetButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const PresetNotificationSheet()),
      child: GradientCard(
        padding: const EdgeInsets.all(16),
        colors: [AppTheme.accent.withOpacity(0.12), AppTheme.surfaceElevated],
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.notifications_active_rounded, color: AppTheme.accent, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Send a Preset Notification', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            Text('Ping all your friends instantly', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 20),
        ]),
      ),
    );
  }
}

// ── Recent Notifications Preview (preset + poke only, today only) ─────────────
class _RecentNotificationsPreview extends StatelessWidget {
  final String groupId;
  const _RecentNotificationsPreview({required this.groupId});

  @override
  Widget build(BuildContext context) {
    // Listen to Realtime DB chat — filter to only isPreset=true + isFixed=true messages from today
    final todayStart = DateTime.now();
    final midnightMs = DateTime(todayStart.year, todayStart.month, todayStart.day).millisecondsSinceEpoch;

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance
          .ref('chats/$groupId/messages')
          .orderByChild('timestamp')
          .startAt(midnightMs)
          .onValue,
      builder: (context, snapshot) {
        List<Map<String, dynamic>> msgs = [];
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final raw = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
          msgs = raw.values
              .map((v) => Map<String, dynamic>.from(v as Map))
              // Only show fixed preset notifications + poke messages in this section
              .where((m) {
                final isPreset = m['isPreset'] == true;
                final isFixed = m['isFixed'] == true;
                final isPoke = m['isPoke'] == true;
                return (isPreset && isFixed) || isPoke;
              })
              .toList()
            ..sort((a, b) => (b['timestamp'] as int? ?? 0).compareTo(a['timestamp'] as int? ?? 0));
          msgs = msgs.take(5).toList();
        }

        if (msgs.isEmpty) {
          return GradientCard(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              const Icon(Icons.notifications_none_rounded, color: AppTheme.textHint, size: 18), const SizedBox(width: 10),
              Text('No notifications today.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textHint)),
            ]),
          ));
        }

        return GradientCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(children: List.generate(msgs.length, (i) {
            final data = msgs[i];
            final name = data['senderName'] as String? ?? '';
            final text = data['text'] as String? ?? '';
            final ts = data['timestamp'] as int? ?? 0;
            final time = ts > 0 ? _formatTime(DateTime.fromMillisecondsSinceEpoch(ts)) : '';
            return Padding(
              padding: EdgeInsets.only(bottom: i < msgs.length - 1 ? 10 : 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), shape: BoxShape.circle),
                  child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '📢', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(name, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    const SizedBox(width: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('Preset', style: GoogleFonts.inter(fontSize: 9, color: AppTheme.accent, fontWeight: FontWeight.w600))),
                    const Spacer(),
                    Text(time, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textHint)),
                  ]),
                  const SizedBox(height: 2),
                  Text(text, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
              ]),
            );
          })),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Personal Reminders Section ────────────────────────────────────────────────
class _PersonalRemindersSection extends StatefulWidget {
  final UserModel user;
  const _PersonalRemindersSection({required this.user});
  @override
  State<_PersonalRemindersSection> createState() => _PersonalRemindersSectionState();
}

class _PersonalRemindersSectionState extends State<_PersonalRemindersSection> {
  List<PersonalReminder> get _reminders => widget.user.personalReminders;

  Future<void> _save(List<PersonalReminder> updated) async {
    await context.read<AuthService>().updatePersonalReminders(updated);
  }

  void _showAddDialog([PersonalReminder? existing, int? idx]) {
    final textCtrl = TextEditingController(text: existing?.text ?? '');
    int startDay = existing?.startDay ?? 1;
    int endDay = existing?.endDay ?? 5;
    String? err;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        title: Text(existing == null ? 'Add Reminder' : 'Edit Reminder',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: textCtrl, maxLines: 2, autofocus: true,
            decoration: const InputDecoration(hintText: 'Reminder text...')),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Start day', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
              DropdownButton<int>(
                value: startDay, isExpanded: true,
                items: List.generate(28, (i) => DropdownMenuItem(value: i+1, child: Text('${i+1}'))),
                onChanged: (v) => ss(() => startDay = v!),
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('End day', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
              DropdownButton<int>(
                value: endDay, isExpanded: true,
                items: List.generate(28, (i) => DropdownMenuItem(value: i+1, child: Text('${i+1}'))),
                onChanged: (v) => ss(() => endDay = v!),
              ),
            ])),
          ]),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(err!, style: const TextStyle(color: AppTheme.error, fontSize: 12))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final text = textCtrl.text.trim();
              if (text.isEmpty) { ss(() => err = 'Enter reminder text.'); return; }
              if (endDay < startDay) { ss(() => err = 'End day must be ≥ start day.'); return; }
              final r = PersonalReminder(
                id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                text: text, startDay: startDay, endDay: endDay,
              );
              final updated = List<PersonalReminder>.from(_reminders);
              if (idx != null) updated[idx] = r; else updated.add(r);
              Navigator.pop(ctx);
              _save(updated);
            },
            child: const Text('Save'),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('My Reminders', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        TextButton.icon(
          onPressed: _reminders.length < 5 ? () => _showAddDialog() : null,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text('Add', style: GoogleFonts.inter(fontSize: 13)),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primary, padding: EdgeInsets.zero),
        ),
      ]),
      if (_reminders.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('No personal reminders. Add one to see it here during set dates.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textHint)),
        )
      else
        ..._reminders.asMap().entries.map((e) {
          final r = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.person_pin_rounded, color: AppTheme.primary, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.text, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary)),
                Text('Day ${r.startDay}–${r.endDay} each month',
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textHint)),
              ])),
              IconButton(icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.textHint),
                onPressed: () => _showAddDialog(r, e.key), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error),
                onPressed: () {
                  final updated = List<PersonalReminder>.from(_reminders)..removeAt(e.key);
                  _save(updated);
                },
                padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]),
          );
        }),
    ]);
  }
}
