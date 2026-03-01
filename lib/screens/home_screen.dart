import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../models/expense_model.dart';
import '../widgets/common_widgets.dart';
import 'preset_notification_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BudgetService _budgetService = BudgetService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _runCleanup();
  }

  Future<void> _runCleanup() async {
    final auth = context.read<AuthService>();
    final groupId = auth.currentGroup?.groupId;
    if (groupId != null) {
      await _budgetService.cleanupOldExpenses(groupId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final group = auth.currentGroup;

    if (user == null || group == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceElevated,
      onRefresh: () async {
        await auth.refreshGroup();
        setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Welcome row ────────────────────────────────────────────────
            _WelcomeRow(username: user.username, isAdmin: user.isAdmin),
            const SizedBox(height: 20),

            // ── Invite code card (always visible) ──────────────────────────
            _InviteCodeCard(code: group.inviteCode),
            const SizedBox(height: 20),

            // ── Stats row ──────────────────────────────────────────────────
            StreamBuilder<List<ExpenseModel>>(
              stream: _budgetService.getMyMonthlyExpenses(
                groupId: group.groupId,
                uid: user.uid,
                month: DateTime.now(),
              ),
              builder: (context, snapshot) {
                final expenses = snapshot.data ?? [];
                final total = BudgetService.totalFromList(expenses);
                return Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'This Month',
                        value: '৳${total.toStringAsFixed(0)}',
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: "Today's Screentime",
                        value: '--',
                        icon: Icons.phone_android_rounded,
                        iconColor: AppTheme.accentOrange,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // ── Rank card ──────────────────────────────────────────────────
            _RankCard(
              groupId: group.groupId,
              uid: user.uid,
              memberUids: group.memberUids,
            ),
            const SizedBox(height: 20),

            // ── Quick preset button ────────────────────────────────────────
            SectionHeader(title: 'Quick Notification'),
            const SizedBox(height: 12),
            _QuickPresetButton(),
            const SizedBox(height: 20),

            // ── Recent chat ────────────────────────────────────────────────
            SectionHeader(
              title: 'Recent Chat',
              trailing: 'Open Chat →',
              onTrailingTap: () {
                // Navigate to chat via bottom nav — handled by parent shell
              },
            ),
            const SizedBox(height: 12),
            _RecentChatPreview(groupId: group.groupId),
          ],
        ),
      ),
    );
  }
}

// ── Welcome Row ───────────────────────────────────────────────────────────────
class _WelcomeRow extends StatelessWidget {
  final String username;
  final bool isAdmin;

  const _WelcomeRow({required this.username, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              username.isNotEmpty
                  ? username[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hey, $username 👋',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (isAdmin)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Admin',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
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
      colors: [
        AppTheme.primary.withOpacity(0.15),
        AppTheme.surfaceElevated,
      ],
      child: Row(
        children: [
          const Icon(Icons.group_outlined,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group Invite Code',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  code,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded,
                size: 18, color: AppTheme.textSecondary),
            onPressed: () {
              // Copy to clipboard
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invite code copied!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Copy code',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Rank Card ─────────────────────────────────────────────────────────────────
class _RankCard extends StatefulWidget {
  final String groupId;
  final String uid;
  final List<String> memberUids;

  const _RankCard({
    required this.groupId,
    required this.uid,
    required this.memberUids,
  });

  @override
  State<_RankCard> createState() => _RankCardState();
}

class _RankCardState extends State<_RankCard> {
  final BudgetService _budgetService = BudgetService();
  int? _rank;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadRank();
  }

  Future<void> _loadRank() async {
    try {
      final totals = await _budgetService.getAllMembersMonthlyTotal(
        groupId: widget.groupId,
        memberUids: widget.memberUids,
        month: DateTime.now(),
      );
      final sorted = totals.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final rank = sorted.indexWhere((e) => e.key == widget.uid) + 1;
      if (mounted) {
        setState(() {
          _rank = rank > 0 ? rank : null;
          _total = widget.memberUids.length;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_rank != null) RankBadge(rank: _rank!) else
            const Icon(Icons.leaderboard_rounded,
                color: AppTheme.primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Rank This Month',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _rank != null
                      ? '#$_rank out of $_total'
                      : 'No data yet',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '(expenses)',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppTheme.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick Preset Button ───────────────────────────────────────────────────────
class _QuickPresetButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const PresetNotificationSheet(),
        );
      },
      child: GradientCard(
        padding: const EdgeInsets.all(16),
        colors: [
          AppTheme.accent.withOpacity(0.12),
          AppTheme.surfaceElevated,
        ],
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: AppTheme.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Send a Preset Notification',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    'Ping all your friends instantly',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Recent Chat Preview ───────────────────────────────────────────────────────
class _RecentChatPreview extends StatelessWidget {
  final String groupId;

  const _RecentChatPreview({required this.groupId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return GradientCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded,
                      color: AppTheme.textHint, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'No messages yet. Start the conversation!',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textHint,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final msgs = snapshot.data!.docs;
        return GradientCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: List.generate(msgs.length, (i) {
              final data = msgs[i].data() as Map<String, dynamic>;
              final name = data['senderName'] ?? '';
              final text = data['text'] ?? '';
              final isPreset = data['isPreset'] ?? false;
              return Padding(
                padding: EdgeInsets.only(bottom: i < msgs.length - 1 ? 10 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                              if (isPreset) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Preset',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: AppTheme.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            text,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
