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
    _tabController = TabController(length: 2, vsync: this);
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

    return Column(children: [
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
            indicator: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
            tabs: const [Tab(text: '💰 Expenses'), Tab(text: '📱 Screentime')],
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
              currentUid: auth.currentUser?.uid ?? '',
            ),
            _ScreentimeLeaderboard(
              groupId: group.groupId,
              memberUids: group.memberUids,
              currentUid: auth.currentUser?.uid ?? '',
              groupDefaultMinutes: group.defaultScreentimeMinutes,
            ),
          ],
        ),
      ),
    ]);
  }
}

// ── Period labels: Today / Weekly / This Month / Last Month ──────────────────
const _kPeriodLabels = ['Today', 'Weekly', 'This Month', 'Last Month'];

Widget _periodSelector({required int selected, required void Function(int) onSelect}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: List.generate(_kPeriodLabels.length, (i) {
        final isSel = selected == i;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSel ? AppTheme.primary : AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSel ? AppTheme.primary : AppTheme.divider),
              ),
              child: Text(
                _kPeriodLabels[i],
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSel ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        );
      }),
    ),
  );
}

// ─── Expense Leaderboard ──────────────────────────────────────────────────────
// Each row shows total only. Tap to expand and see TYPE breakdown (yoyo method style).

class _ExpenseLeaderboard extends StatefulWidget {
  final String groupId;
  final List<String> memberUids;
  final String currentUid;

  const _ExpenseLeaderboard({
    required this.groupId,
    required this.memberUids,
    required this.currentUid,
  });

  @override
  State<_ExpenseLeaderboard> createState() => _ExpenseLeaderboardState();
}

class _ExpenseLeaderboardState extends State<_ExpenseLeaderboard> {
  final BudgetService _budgetService = BudgetService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 0=today, 1=weekly, 2=this month, 3=last month
  int _period = 0;
  bool _loading = true;
  Map<String, double> _totals = {};
  Map<String, String> _names = {};
  // uid → expanded state
  final Set<String> _expanded = {};
  // uid → type totals (loaded on expand)
  final Map<String, Map<String, double>> _typeTotals = {};
  final Set<String> _loadingTypes = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _targetDay {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _weekStart => BudgetService.currentWeekStart;

  DateTime get _targetMonth {
    final n = DateTime.now();
    // period 2 = this month, period 3 = last month
    return DateTime(n.year, n.month - (_period - 2), 1);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _expanded.clear(); _typeTotals.clear(); });
    try {
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
      _names = names;

      Map<String, double> totals;
      switch (_period) {
        case 0:
          totals = await _budgetService.getAllMembersDailyTotal(
            groupId: widget.groupId, memberUids: widget.memberUids, day: _targetDay);
          break;
        case 1:
          totals = await _budgetService.getAllMembersWeeklyTotal(
            groupId: widget.groupId, memberUids: widget.memberUids, weekStart: _weekStart);
          break;
        case 2:
        case 3:
          totals = await _budgetService.getAllMembersMonthlyTotal(
            groupId: widget.groupId, memberUids: widget.memberUids, month: _targetMonth);
          break;
        default:
          totals = {};
      }
      _totals = totals;
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTypeBreakdown(String uid) async {
    if (_typeTotals.containsKey(uid)) return;
    setState(() => _loadingTypes.add(uid));
    try {
      Map<String, Map<String, double>> result;
      switch (_period) {
        case 0:
          result = await _budgetService.getAllMembersTypeTotalForDay(
            groupId: widget.groupId, memberUids: [uid], day: _targetDay);
          break;
        case 1:
          result = await _budgetService.getAllMembersTypeTotalForWeek(
            groupId: widget.groupId, memberUids: [uid], weekStart: _weekStart);
          break;
        default:
          result = await _budgetService.getAllMembersTypeTotalForMonth(
            groupId: widget.groupId, memberUids: [uid], month: _targetMonth);
      }
      if (mounted) {
        setState(() {
          _typeTotals[uid] = result[uid] ?? {};
          _loadingTypes.remove(uid);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTypes.remove(uid));
    }
  }

  void _toggleExpand(String uid) {
    setState(() {
      if (_expanded.contains(uid)) {
        _expanded.remove(uid);
      } else {
        _expanded.add(uid);
        _loadTypeBreakdown(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _totals.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceElevated,
      onRefresh: _load,
      child: Column(children: [
        const SizedBox(height: 8),
        _periodSelector(selected: _period, onSelect: (i) {
          setState(() => _period = i);
          _load();
        }),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
            : sorted.isEmpty
              ? const EmptyState(icon: Icons.leaderboard_outlined, title: 'No data', subtitle: 'No expenses for this period.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    ...sorted.asMap().entries.map((entry) {
                      final rank = entry.key + 1;
                      final uid = entry.value.key;
                      final total = entry.value.value;
                      final isMe = uid == widget.currentUid;
                      final name = _names[uid] ?? 'Unknown';
                      final isExpanded = _expanded.contains(uid);
                      final isLoadingType = _loadingTypes.contains(uid);
                      final types = _typeTotals[uid] ?? {};

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ExpenseRankCard(
                          rank: rank,
                          name: name,
                          total: total,
                          isMe: isMe,
                          isExpanded: isExpanded,
                          isLoadingTypes: isLoadingType,
                          typeTotals: types,
                          onTap: () => _toggleExpand(uid),
                        ),
                      );
                    }),
                    Center(
                      child: Text(
                        '🥇 = Lowest spender wins  •  Tap to see breakdown',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textHint),
                      ),
                    ),
                  ],
                ),
        ),
      ]),
    );
  }
}

class _ExpenseRankCard extends StatelessWidget {
  final int rank;
  final String name;
  final double total;
  final bool isMe;
  final bool isExpanded;
  final bool isLoadingTypes;
  final Map<String, double> typeTotals;
  final VoidCallback onTap;

  const _ExpenseRankCard({
    required this.rank,
    required this.name,
    required this.total,
    required this.isMe,
    required this.isExpanded,
    required this.isLoadingTypes,
    required this.typeTotals,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isMe
              ? [AppTheme.primary.withOpacity(0.18), AppTheme.surfaceElevated]
              : [AppTheme.surfaceElevated, AppTheme.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMe ? AppTheme.primary.withOpacity(0.4) : Colors.white.withOpacity(0.04),
            width: isMe ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Main row
            Row(children: [
              SizedBox(width: 36, child: Center(child: RankBadge(rank: rank))),
              const SizedBox(width: 10),
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: isMe ? AppTheme.primary.withOpacity(0.2) : AppTheme.surfaceHighlight,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isMe ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Row(children: [
                Flexible(
                  child: Text(
                    name,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
                    child: Text('You', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                  ),
                ],
              ])),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '৳${total.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: rank == 1 ? AppTheme.accentYellow : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppTheme.textHint,
                ),
              ]),
            ]),

            // Expanded: type breakdown (yoyo method style)
            if (isExpanded) ...[
              const SizedBox(height: 12),
              const Divider(color: AppTheme.divider, height: 1),
              const SizedBox(height: 10),
              if (isLoadingTypes)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                    ),
                  ),
                )
              else if (typeTotals.isEmpty)
                Text('No category breakdown.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textHint))
              else
                ...typeTotals.entries.map((e) {
                  final pct = total > 0 ? (e.value / total).clamp(0.0, 1.0) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(e.key, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                        Text('৳${e.value.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: AppTheme.surfaceHighlight,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          minHeight: 4,
                        ),
                      ),
                    ]),
                  );
                }),
            ],
          ]),
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
  State<_ScreentimeLeaderboard> createState() => _ScreentimeLeaderboardState();
}

class _ScreentimeLeaderboardState extends State<_ScreentimeLeaderboard> {
  final ScreentimeService _service = ScreentimeService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 0=today, 1=weekly, 2=this month, 3=last month
  int _period = 0;
  bool _loading = true;
  Map<String, String> _names = {};

  // Today
  List<_DailyEntry> _dailyEntries = [];

  // Weekly / Monthly: uid → {total, days}
  Map<String, int> _periodTotals = {};
  Map<String, int> _periodDays = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _weekStart => ScreentimeService.weekStart;

  DateTime get _targetMonth {
    final n = DateTime.now();
    return DateTime(n.year, n.month - (_period - 2), 1);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Load names
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
      _names = names;

      if (_period == 0) {
        // Today
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);
        final entries = <_DailyEntry>[];
        for (final uid in widget.memberUids) {
          int todayMinutes = 0;
          try {
            final snap = await _db
                .collection('groups').doc(widget.groupId)
                .collection('screentime')
                .where('uid', isEqualTo: uid)
                .where('date', isGreaterThanOrEqualTo: todayStart.toIso8601String())
                .where('date', isLessThan: todayStart.add(const Duration(days: 1)).toIso8601String())
                .limit(1).get();
            if (snap.docs.isNotEmpty) {
              todayMinutes = (snap.docs.first.data()['totalMinutes'] as num?)?.toInt() ?? 0;
            }
          } catch (_) {}
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
        _dailyEntries = entries;
      } else {
        // Weekly or Monthly
        Map<String, int> totals;
        DateTime rangeStart;
        DateTime rangeEnd;

        if (_period == 1) {
          // Weekly
          rangeStart = _weekStart;
          rangeEnd = rangeStart.add(const Duration(days: 7));
          totals = await _service.getAllMembersWeeklyScreentime(
            groupId: widget.groupId,
            memberUids: widget.memberUids,
            weekStart: rangeStart,
          );
        } else {
          // Monthly
          rangeStart = DateTime(_targetMonth.year, _targetMonth.month, 1);
          rangeEnd = DateTime(_targetMonth.year, _targetMonth.month + 1, 1);
          totals = await _service.getAllMembersMonthlyScreentime(
            groupId: widget.groupId,
            memberUids: widget.memberUids,
            month: _targetMonth,
          );
        }

        // Count days with data for each user → daily average
        final snap = await _db
            .collection('groups').doc(widget.groupId)
            .collection('screentime')
            .where('date', isGreaterThanOrEqualTo: rangeStart.toIso8601String())
            .where('date', isLessThan: rangeEnd.toIso8601String())
            .get();
        final daysCount = <String, int>{};
        for (final doc in snap.docs) {
          final uid = doc.data()['uid'] as String? ?? '';
          if (totals.containsKey(uid)) daysCount[uid] = (daysCount[uid] ?? 0) + 1;
        }

        _periodTotals = totals;
        _periodDays = daysCount;
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPokeSheet(BuildContext context, String uid, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PokeSheet(targetUid: uid, targetName: name, groupId: widget.groupId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceElevated,
      onRefresh: _load,
      child: Column(children: [
        const SizedBox(height: 8),
        _periodSelector(selected: _period, onSelect: (i) {
          setState(() => _period = i);
          _load();
        }),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
            : _period == 0
              ? _buildTodayList(context)
              : _buildPeriodList(context),
        ),
      ]),
    );
  }

  Widget _buildTodayList(BuildContext context) {
    if (_dailyEntries.isEmpty) {
      return const EmptyState(icon: Icons.today_rounded, title: 'No data for today', subtitle: 'Open the app to sync screentime.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        ..._dailyEntries.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final item = entry.value;
          final isMe = item.uid == widget.currentUid;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ScreentimeTile(
              rank: rank,
              name: item.name,
              totalMinutes: item.todayMinutes,
              avgMinutes: null,
              isMe: isMe,
              showPoke: !isMe && item.exceeded,
              onPoke: () => _showPokeSheet(context, item.uid, item.name),
              subtitle: 'Limit: ${ScreentimeService.formatMinutes(item.limitMinutes)}',
            ),
          );
        }),
        Center(
          child: Text(
            '🥇 = Lowest screentime wins  •  👆 = Poke when over limit',
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textHint),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodList(BuildContext context) {
    final sorted = _periodTotals.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (sorted.isEmpty) {
      return const EmptyState(icon: Icons.phone_android_rounded, title: 'No screentime data', subtitle: 'Open the app each day to sync.');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        ...sorted.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final uid = entry.value.key;
          final minutes = entry.value.value;
          final isMe = uid == widget.currentUid;
          final days = _periodDays[uid] ?? 1;
          final avgMinutes = days > 0 ? (minutes / days).round() : 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ScreentimeTile(
              rank: rank,
              name: _names[uid] ?? 'Unknown',
              totalMinutes: minutes,
              avgMinutes: avgMinutes,
              isMe: isMe,
              showPoke: false,
              subtitle: _kPeriodLabels[_period],
            ),
          );
        }),
        Center(
          child: Text(
            '🥇 = Lowest screentime wins',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textHint),
          ),
        ),
      ],
    );
  }
}

// ─── Screentime tile with optional daily average below ────────────────────────
class _ScreentimeTile extends StatelessWidget {
  final int rank;
  final String name;
  final int totalMinutes;
  final int? avgMinutes; // null = don't show average
  final bool isMe;
  final bool showPoke;
  final VoidCallback? onPoke;
  final String subtitle;

  const _ScreentimeTile({
    required this.rank,
    required this.name,
    required this.totalMinutes,
    required this.avgMinutes,
    required this.isMe,
    required this.showPoke,
    required this.subtitle,
    this.onPoke,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isMe
            ? [AppTheme.primary.withOpacity(0.18), AppTheme.surfaceElevated]
            : [AppTheme.surfaceElevated, AppTheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? AppTheme.primary.withOpacity(0.4) : Colors.white.withOpacity(0.04),
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          SizedBox(width: 36, child: Center(child: RankBadge(rank: rank))),
          const SizedBox(width: 12),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isMe ? AppTheme.primary.withOpacity(0.2) : AppTheme.surfaceHighlight,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: isMe ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(
                  name,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
                  child: Text('You', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                ),
              ],
            ]),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textHint)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              ScreentimeService.formatMinutes(totalMinutes),
              style: GoogleFonts.inter(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: rank == 1 ? AppTheme.accentYellow : AppTheme.textPrimary,
              ),
            ),
            // Daily average in brackets below total
            if (avgMinutes != null)
              Text(
                '(${ScreentimeService.formatMinutes(avgMinutes!)}/day)',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textHint),
              ),
            if (showPoke) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onPoke,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('👆 Poke', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.accentOrange)),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _DailyEntry {
  final String uid, name;
  final int todayMinutes, limitMinutes;
  final bool exceeded;
  _DailyEntry({required this.uid, required this.name, required this.todayMinutes, required this.limitMinutes, required this.exceeded});
}
