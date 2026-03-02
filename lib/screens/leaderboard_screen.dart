import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/screentime_service.dart';
import '../models/user_model.dart';
import '../widgets/common_widgets.dart';
import 'screentime_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final group = auth.currentGroup;
    if (group == null) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
              tabs: const [
                Tab(text: '💰 Expenses'),
                Tab(text: '📱 Monthly'),
                Tab(text: '📅 Daily'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ExpenseLeaderboard(
                groupId: group.groupId,
                memberUids: group.memberUids,
                expenseTypes: group.expenseTypes,
                currentUid: auth.currentUser?.uid ?? '',
              ),
              _ScreentimeLeaderboard(
                groupId: group.groupId,
                memberUids: group.memberUids,
                currentUid: auth.currentUser?.uid ?? '',
                groupDefaultMinutes: group.defaultScreentimeMinutes,
              ),
              _DailyScreentimeLeaderboard(
                groupId: group.groupId,
                memberUids: group.memberUids,
                currentUid: auth.currentUser?.uid ?? '',
                groupDefaultMinutes: group.defaultScreentimeMinutes,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Expense Leaderboard ──────────────────────────────────────────────────────
class _ExpenseLeaderboard extends StatefulWidget {
  final String groupId;
  final List<String> memberUids;
  final List<String> expenseTypes;
  final String currentUid;

  const _ExpenseLeaderboard({
    required this.groupId,
    required this.memberUids,
    required this.expenseTypes,
    required this.currentUid,
  });

  @override
  State<_ExpenseLeaderboard> createState() => _ExpenseLeaderboardState();
}

class _ExpenseLeaderboardState extends State<_ExpenseLeaderboard> {
  final BudgetService _budgetService = BudgetService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // null = overall, otherwise the type string
  String? _selectedType;
  bool _loading = true;
  List<_RankEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Load all usernames first
      final userDocs = await Future.wait(
        widget.memberUids.map((uid) => _db.collection('users').doc(uid).get()),
      );
      final names = <String, String>{};
      for (final doc in userDocs) {
        if (doc.exists) {
          final u = UserModel.fromMap(doc.data()!);
          names[u.uid] = u.username;
        }
      }

      Map<String, double> totals;
      if (_selectedType == null) {
        totals = await _budgetService.getAllMembersMonthlyTotal(
          groupId: widget.groupId,
          memberUids: widget.memberUids,
          month: DateTime.now(),
        );
      } else {
        final typeData =
            await _budgetService.getAllMembersTypeMonthlyTotal(
          groupId: widget.groupId,
          memberUids: widget.memberUids,
          types: [_selectedType!],
          month: DateTime.now(),
        );
        totals = typeData[_selectedType!] ?? {};
      }

      final entries = totals.entries
          .map((e) => _RankEntry(
                uid: e.key,
                name: names[e.key] ?? 'Unknown',
                value: e.value,
              ))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceElevated,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month label
            _MonthLabel(),
            const SizedBox(height: 12),

            // Type filter chips
            _TypeFilter(
              types: widget.expenseTypes,
              selected: _selectedType,
              onSelected: (type) {
                setState(() => _selectedType = type);
                _load();
              },
            ),
            const SizedBox(height: 16),

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2),
                ),
              )
            else if (_entries.isEmpty)
              const EmptyState(
                icon: Icons.leaderboard_outlined,
                title: 'No data this month',
                subtitle: 'Start adding expenses to see rankings!',
              )
            else
              ..._entries.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final item = entry.value;
                final isMe = item.uid == widget.currentUid;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LeaderboardTile(
                    rank: rank,
                    name: item.name,
                    value: '৳${item.value.toStringAsFixed(0)}',
                    isMe: isMe,
                    subtitle: _selectedType ?? 'Overall',
                    showPoke: false,
                  ),
                );
              }),

            const SizedBox(height: 8),
            Center(
              child: Text(
                '🥇 = Lowest spender wins',
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppTheme.textHint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Screentime Leaderboard ───────────────────────────────────────────────────
class _ScreentimeLeaderboard extends StatefulWidget {
  final String groupId;
  final List<String> memberUids;
  final String currentUid;
  final int groupDefaultMinutes;

  const _ScreentimeLeaderboard({
    required this.groupId,
    required this.memberUids,
    required this.currentUid,
    this.groupDefaultMinutes = 180,
  });

  @override
  State<_ScreentimeLeaderboard> createState() =>
      _ScreentimeLeaderboardState();
}

class _ScreentimeLeaderboardState extends State<_ScreentimeLeaderboard> {
  final ScreentimeService _service = ScreentimeService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _loading = true;
  List<_RankEntry> _entries = [];
  // 0 = this month, 1 = last month, 2 = two months ago
  int _selectedMonth = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _targetMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month - _selectedMonth, 1);
  }

  String get _monthLabel {
    if (_selectedMonth == 0) return 'This Month';
    if (_selectedMonth == 1) return 'Last Month';
    final m = _targetMonth;
    const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[m.month]} ${m.year}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userDocs = await Future.wait(
        widget.memberUids.map((uid) => _db.collection('users').doc(uid).get()),
      );
      final names = <String, String>{};
      for (final doc in userDocs) {
        if (doc.exists) {
          final u = UserModel.fromMap(doc.data() as Map<String, dynamic>);
          names[u.uid] = u.username;
        }
      }

      final totals = await _service.getAllMembersMonthlyScreentime(
        groupId: widget.groupId,
        memberUids: widget.memberUids,
        month: _targetMonth,
      );

      final entries = totals.entries
          .map((e) => _RankEntry(
                uid: e.key,
                name: names[e.key] ?? 'Unknown',
                value: e.value.toDouble(),
              ))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceElevated,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // Month selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [0, 1, 2].map((i) {
                final selected = _selectedMonth == i;
                final labels = ['This Month', 'Last Month', '2 Months Ago'];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () {
                      if (_selectedMonth != i) {
                        setState(() => _selectedMonth = i);
                        _load();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.primary : AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        labels[i],
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2),
                ),
              )
            else if (_entries.isEmpty)
              const EmptyState(
                icon: Icons.phone_android_rounded,
                title: 'No screentime data yet',
                subtitle: 'Open the app each day to sync your screentime.',
              )
            else
              ..._entries.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final item = entry.value;
                final isMe = item.uid == widget.currentUid;
                final minutes = item.value.toInt();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LeaderboardTile(
                    rank: rank,
                    name: item.name,
                    value: ScreentimeService.formatMinutes(minutes),
                    isMe: isMe,
                    subtitle: _monthLabel,
                    showPoke: false, // No poke on monthly — only on daily tab
                  ),
                );
              }),

            const SizedBox(height: 8),
            Center(
              child: Text(
                '🥇 = Lowest screentime wins',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textHint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Daily Screentime Leaderboard (with Poke) ─────────────────────────────────
class _DailyScreentimeLeaderboard extends StatefulWidget {
  final String groupId;
  final List<String> memberUids;
  final String currentUid;
  final int groupDefaultMinutes;

  const _DailyScreentimeLeaderboard({
    required this.groupId,
    required this.memberUids,
    required this.currentUid,
    this.groupDefaultMinutes = 180,
  });

  @override
  State<_DailyScreentimeLeaderboard> createState() =>
      _DailyScreentimeLeaderboardState();
}

class _DailyScreentimeLeaderboardState extends State<_DailyScreentimeLeaderboard> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _loading = true;

  // uid -> {minutes, limitMinutes, exceeded}
  List<_DailyEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Load member names
      final userDocs = await Future.wait(
        widget.memberUids.map((uid) => _db.collection('users').doc(uid).get()),
      );
      final names = <String, String>{};
      for (final doc in userDocs) {
        if (doc.exists) {
          final u = UserModel.fromMap(doc.data() as Map<String, dynamic>);
          names[u.uid] = u.username;
        }
      }

      final entries = <_DailyEntry>[];
      for (final uid in widget.memberUids) {
        // Get today's total
        int todayMinutes = 0;
        try {
          final snap = await _db
              .collection('groups')
              .doc(widget.groupId)
              .collection('screentime')
              .where('uid', isEqualTo: uid)
              .where('date', isGreaterThanOrEqualTo: DateTime(today.year, today.month, today.day).toIso8601String())
              .where('date', isLessThan: DateTime(today.year, today.month, today.day + 1).toIso8601String())
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            todayMinutes = (snap.docs.first.data()['totalMinutes'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}

        // Get their personal limit
        int limitMinutes = widget.groupDefaultMinutes;
        try {
          final limitDoc = await _db.collection('userLimits').doc(uid).get();
          if (limitDoc.exists) {
            limitMinutes = (limitDoc.data()?['limitMinutes'] as num?)?.toInt() ?? widget.groupDefaultMinutes;
          }
        } catch (_) {}

        entries.add(_DailyEntry(
          uid: uid,
          name: names[uid] ?? 'Unknown',
          todayMinutes: todayMinutes,
          limitMinutes: limitMinutes,
          exceeded: limitMinutes > 0 && todayMinutes >= limitMinutes,
        ));
      }

      entries.sort((a, b) => a.todayMinutes.compareTo(b.todayMinutes));

      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPokeSheet(BuildContext context, String uid, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PokeSheet(
        targetUid: uid,
        targetName: name,
        groupId: widget.groupId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceElevated,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                ),
              )
            else if (_entries.isEmpty)
              const EmptyState(
                icon: Icons.today_rounded,
                title: 'No data for today',
                subtitle: 'Data appears after syncing screentime.',
              )
            else
              ..._entries.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final item = entry.value;
                final isMe = item.uid == widget.currentUid;
                final limitStr = ScreentimeService.formatMinutes(item.limitMinutes);
                final usedStr = ScreentimeService.formatMinutes(item.todayMinutes);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LeaderboardTile(
                    rank: rank,
                    name: item.name,
                    value: usedStr,
                    isMe: isMe,
                    subtitle: 'Limit: $limitStr',
                    showPoke: !isMe && item.exceeded,
                    onPoke: () => _showPokeSheet(context, item.uid, item.name),
                    exceeded: item.exceeded,
                  ),
                );
              }),

            const SizedBox(height: 8),
            Center(
              child: Text(
                '🥇 = Lowest daily screentime wins  •  👆 = Poke when over limit',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textHint),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyEntry {
  final String uid;
  final String name;
  final int todayMinutes;
  final int limitMinutes;
  final bool exceeded;
  _DailyEntry({
    required this.uid,
    required this.name,
    required this.todayMinutes,
    required this.limitMinutes,
    required this.exceeded,
  });
}

// ─── Shared widgets ───────────────────────────────────────────────────────────
class _LeaderboardTile extends StatelessWidget {
  final int rank;
  final String name;
  final String value;
  final bool isMe;
  final String subtitle;
  final bool showPoke;
  final VoidCallback? onPoke;
  final bool exceeded;

  const _LeaderboardTile({
    required this.rank,
    required this.name,
    required this.value,
    required this.isMe,
    required this.subtitle,
    required this.showPoke,
    this.onPoke,
    this.exceeded = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isMe
              ? [
                  AppTheme.primary.withOpacity(0.18),
                  AppTheme.surfaceElevated,
                ]
              : [AppTheme.surfaceElevated, AppTheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? AppTheme.primary.withOpacity(0.4)
              : Colors.white.withOpacity(0.04),
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Rank badge
            SizedBox(width: 36, child: Center(child: RankBadge(rank: rank))),
            const SizedBox(width: 12),

            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.primary.withOpacity(0.2)
                    : AppTheme.surfaceHighlight,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color:
                        isMe ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'You',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),

            // Value
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: rank == 1
                        ? AppTheme.accentYellow
                        : AppTheme.textPrimary,
                  ),
                ),
                if (showPoke) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onPoke,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '👆 Poke',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentOrange,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return Row(
      children: [
        const Icon(Icons.calendar_month_rounded,
            size: 14, color: AppTheme.textHint),
        const SizedBox(width: 6),
        Text(
          '${months[now.month]} ${now.year}',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppTheme.textHint,
          ),
        ),
      ],
    );
  }
}

class _TypeFilter extends StatelessWidget {
  final List<String> types;
  final String? selected;
  final void Function(String?) onSelected;

  const _TypeFilter({
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final all = ['Overall', ...types];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final label = all[i];
          final isSelected =
              (i == 0 && selected == null) || label == selected;
          return GestureDetector(
            onTap: () => onSelected(i == 0 ? null : label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary
                    : AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      isSelected ? AppTheme.primary : AppTheme.divider,
                  width: 1,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color:
                      isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RankEntry {
  final String uid;
  final String name;
  final double value;

  const _RankEntry(
      {required this.uid, required this.name, required this.value});
}
