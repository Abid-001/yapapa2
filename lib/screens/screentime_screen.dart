import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/screentime_service.dart';
import '../models/screentime_model.dart';
import '../models/user_model.dart';
import '../widgets/common_widgets.dart';

class ScreentimeScreen extends StatefulWidget {
  const ScreentimeScreen({super.key});

  @override
  State<ScreentimeScreen> createState() => _ScreentimeScreenState();
}

class _ScreentimeScreenState extends State<ScreentimeScreen>
    with SingleTickerProviderStateMixin {
  final ScreentimeService _service = ScreentimeService();
  late TabController _tabController;

  int? _dailyLimitMinutes;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLimit();
    _syncOnOpen();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLimit() async {
    final auth = context.read<AuthService>();
    final groupDefault = auth.currentGroup?.defaultScreentimeMinutes ?? 180;
    final limit = await _service.getDailyLimit(groupDefault: groupDefault);
    if (mounted) setState(() => _dailyLimitMinutes = limit);
  }

  Future<void> _syncOnOpen() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final group = auth.currentGroup;
    if (user == null || group == null) return;

    setState(() => _syncing = true);
    await _service.syncTodayScreentime(
      uid: user.uid,
      groupId: group.groupId,
      dailyLimitMinutes: _dailyLimitMinutes,
    );
    await _service.cleanupOldScreentime(group.groupId);
    if (mounted) setState(() => _syncing = false);
  }

  void _showSetLimitDialog() {
    final existingH = _dailyLimitMinutes != null ? _dailyLimitMinutes! ~/ 60 : 0;
    final existingM = _dailyLimitMinutes != null ? _dailyLimitMinutes! % 60 : 0;
    final hCtrl = TextEditingController(text: existingH > 0 ? existingH.toString() : '');
    final mCtrl = TextEditingController(text: existingM > 0 ? existingM.toString() : '');
    final hFocus = FocusNode();
    String? dialogError;
    WidgetsBinding.instance.addPostFrameCallback((_) => hFocus.requestFocus());
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Set Daily Limit', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'When you exceed this limit, your friends will be notified automatically.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  // Hours box
                  Expanded(
                    child: TextField(
                      controller: hCtrl,
                      focusNode: hFocus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        hintText: '0',
                        suffixText: 'h',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Mins box
                  Expanded(
                    child: TextField(
                      controller: mCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        // Max 59 minutes
                        TextInputFormatter.withFunction((old, newVal) {
                          final v = int.tryParse(newVal.text) ?? 0;
                          if (v > 59) return old;
                          return newVal;
                        }),
                      ],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        hintText: '0',
                        suffixText: 'min',
                      ),
                    ),
                  ),
                ]),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
                ],
                const SizedBox(height: 6),
                Text('Max 24h. Minutes 0–59.', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textHint)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              if (_dailyLimitMinutes != null)
                TextButton(
                  onPressed: () async {
                    final uid = context.read<AuthService>().currentUser?.uid;
                    await _service.saveDailyLimit(0, uid: uid);
                    if (mounted) { setState(() => _dailyLimitMinutes = null); Navigator.pop(ctx); }
                  },
                  child: const Text('Remove', style: TextStyle(color: AppTheme.error)),
                ),
              ElevatedButton(
                onPressed: () async {
                  final h = int.tryParse(hCtrl.text.trim()) ?? 0;
                  final m = int.tryParse(mCtrl.text.trim()) ?? 0;
                  final totalMinutes = h * 60 + m;
                  if (totalMinutes <= 0) {
                    setDialogState(() => dialogError = 'Please enter a limit greater than 0.');
                    return;
                  }
                  if (totalMinutes > 24 * 60) {
                    setDialogState(() => dialogError = 'Limit cannot exceed 24 hours.');
                    return;
                  }
                  final uid = context.read<AuthService>().currentUser?.uid;
                  await _service.saveDailyLimit(totalMinutes, uid: uid);
                  if (mounted) { setState(() => _dailyLimitMinutes = totalMinutes); Navigator.pop(ctx); }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final group = auth.currentGroup;
    if (user == null || group == null) return const SizedBox.shrink();

    return Column(
      children: [
        // ── Limit bar + sync indicator ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: GradientCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.timer_outlined,
                      color: AppTheme.accentOrange, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Limit',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      Text(
                        _dailyLimitMinutes != null
                            ? '${ScreentimeService.formatMinutes(_dailyLimitMinutes!)} per day'
                            : 'Not set',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _dailyLimitMinutes != null
                              ? AppTheme.textPrimary
                              : AppTheme.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_syncing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _showSetLimitDialog,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: GoogleFonts.inter(fontSize: 12),
                  ),
                  child: Text(
                    _dailyLimitMinutes != null ? 'Edit' : 'Set',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── Tabs ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                Tab(text: 'Today'),
                Tab(text: 'Weekly'),
                Tab(text: 'Monthly'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _DailyTab(
                  uid: user.uid,
                  groupId: group.groupId,
                  dailyLimitMinutes: _dailyLimitMinutes),
              _WeeklyTab(uid: user.uid, groupId: group.groupId),
              _MonthlyTab(uid: user.uid, groupId: group.groupId),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Daily Tab ────────────────────────────────────────────────────────────────
class _DailyTab extends StatefulWidget {
  final String uid;
  final String groupId;
  final int? dailyLimitMinutes;

  const _DailyTab(
      {required this.uid,
      required this.groupId,
      required this.dailyLimitMinutes});

  @override
  State<_DailyTab> createState() => _DailyTabState();
}

class _DailyTabState extends State<_DailyTab> {
  final ScreentimeService _service = ScreentimeService();
  ScreentimeModel? _today;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // Today = midnight (00:00:00) to next midnight — matches Android battery/screentime
    final todayStart = ScreentimeService.todayStart; // midnight
    final tomorrow = todayStart.add(const Duration(days: 1));
    _service.streamMyScreentime(
      groupId: widget.groupId,
      uid: widget.uid,
      from: todayStart,
      to: tomorrow,
    ).listen((data) {
      if (mounted) {
        setState(() {
          _today = data.isNotEmpty ? data.first : null;
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppTheme.primary, strokeWidth: 2));
    }

    final total = _today?.totalMinutes ?? 0;
    final appUsage = _today?.appUsage ?? {};
    final limit = widget.dailyLimitMinutes;
    final isOverLimit = limit != null && total > limit;

    // Sort apps by usage desc
    final sortedApps = appUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topApps = sortedApps.take(8).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total card
          GradientCard(
            colors: isOverLimit
                ? [
                    AppTheme.error.withOpacity(0.12),
                    AppTheme.surfaceElevated
                  ]
                : [
                    AppTheme.accentOrange.withOpacity(0.12),
                    AppTheme.surfaceElevated
                  ],
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Today's Screentime",
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ScreentimeService.formatMinutes(total),
                            style: GoogleFonts.inter(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: isOverLimit
                                  ? AppTheme.error
                                  : AppTheme.accentOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isOverLimit)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⚠️ Over limit',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
                if (limit != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Daily limit: ${ScreentimeService.formatMinutes(limit)}',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: AppTheme.textHint),
                      ),
                      Text(
                        '${((total / limit) * 100).clamp(0, 999).toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: AppTheme.textHint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: limit > 0
                          ? (total / limit).clamp(0.0, 1.0)
                          : 0,
                      backgroundColor: AppTheme.surfaceHighlight,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isOverLimit
                            ? AppTheme.error
                            : AppTheme.accentOrange,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Top apps
          if (topApps.isEmpty)
            const EmptyState(
              icon: Icons.phone_android_rounded,
              title: 'No usage data yet',
              subtitle:
                  'Usage data will appear here after some phone activity. Make sure to grant Usage Access permission.',
            )
          else ...[
            SectionHeader(title: 'Top Apps Today'),
            const SizedBox(height: 10),
            ...topApps.map((entry) {
              final pct = total > 0
                  ? (entry.value / total).clamp(0.0, 1.0)
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AppUsageRow(
                  appName: entry.key,
                  minutes: entry.value,
                  percentage: pct,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─── Weekly Tab ───────────────────────────────────────────────────────────────
class _WeeklyTab extends StatefulWidget {
  final String uid;
  final String groupId;

  const _WeeklyTab({required this.uid, required this.groupId});

  @override
  State<_WeeklyTab> createState() => _WeeklyTabState();
}

class _WeeklyTabState extends State<_WeeklyTab> {
  final ScreentimeService _service = ScreentimeService();
  List<ScreentimeModel> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final weekStart = ScreentimeService.weekStart;
    final weekEnd = ScreentimeService.weekEnd;
    final data = await _service.getMyScreentime(
      groupId: widget.groupId,
      uid: widget.uid,
      from: weekStart,
      to: weekEnd,
    );
    // Sort oldest first for chart display
    data.sort((a, b) => a.date.compareTo(b.date));
    if (mounted) setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppTheme.primary, strokeWidth: 2));
    }

    final totalMinutes = ScreentimeService.totalMinutesFromList(_data);
    final avgMinutes = _data.isEmpty ? 0 : totalMinutes ~/ _data.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'This Week Total',
                  value: ScreentimeService.formatMinutes(totalMinutes),
                  icon: Icons.calendar_view_week_rounded,
                  iconColor: AppTheme.accentOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Daily Average',
                  value: ScreentimeService.formatMinutes(avgMinutes),
                  icon: Icons.analytics_outlined,
                  iconColor: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Bar chart
          if (_data.isEmpty)
            const EmptyState(
              icon: Icons.bar_chart_rounded,
              title: 'No weekly data yet',
              subtitle: 'Check back after using your phone!',
            )
          else ...[
            SectionHeader(title: 'This Week'),
            const SizedBox(height: 12),
            _WeekBarChart(data: _data),
            const SizedBox(height: 20),

            SectionHeader(title: 'Daily Breakdown'),
            const SizedBox(height: 10),
            ..._data.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DaySummaryTile(model: s),
                )),
          ],
        ],
      ),
    );
  }
}

// ─── Monthly Tab ──────────────────────────────────────────────────────────────
class _MonthlyTab extends StatefulWidget {
  final String uid;
  final String groupId;

  const _MonthlyTab({required this.uid, required this.groupId});

  @override
  State<_MonthlyTab> createState() => _MonthlyTabState();
}

class _MonthlyTabState extends State<_MonthlyTab> {
  final ScreentimeService _service = ScreentimeService();
  List<ScreentimeModel> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final monthStart = ScreentimeService.monthStart;
    final monthEnd = ScreentimeService.monthEnd;
    final data = await _service.getMyScreentime(
      groupId: widget.groupId,
      uid: widget.uid,
      from: monthStart,
      to: monthEnd,
    );
    if (mounted) setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppTheme.primary, strokeWidth: 2));
    }

    final totalMinutes = ScreentimeService.totalMinutesFromList(_data);
    final avgMinutes = _data.isEmpty ? 0 : totalMinutes ~/ _data.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'This Month',
                  value: ScreentimeService.formatMinutes(totalMinutes),
                  icon: Icons.calendar_month_rounded,
                  iconColor: AppTheme.accentOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Daily Average',
                  value: ScreentimeService.formatMinutes(avgMinutes),
                  icon: Icons.analytics_outlined,
                  iconColor: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_data.isEmpty)
            const EmptyState(
              icon: Icons.phone_android_rounded,
              title: 'No monthly data yet',
              subtitle: 'Data builds up over the month.',
            )
          else ...[
            SectionHeader(title: 'All Days This Month'),
            const SizedBox(height: 10),
            ..._data.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DaySummaryTile(model: s),
                )),
          ],
        ],
      ),
    );
  }
}

// ─── Poke Sheet ───────────────────────────────────────────────────────────────
class PokeSheet extends StatefulWidget {
  final String targetUid;
  final String targetName;
  final String groupId;

  const PokeSheet({
    super.key,
    required this.targetUid,
    required this.targetName,
    required this.groupId,
  });

  @override
  State<PokeSheet> createState() => _PokeSheetState();
}

class _PokeSheetState extends State<PokeSheet> {
  bool _sent = false;
  bool _loading = false;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _sendPoke(BuildContext context) async {
    setState(() => _loading = true);
    try {
      // Need current user's name to show in notification
      final auth = context.read<AuthService>();
      final fromName = auth.currentUser?.username ?? 'Someone';
      final fromUid = auth.currentUser?.uid ?? '';
      await _db
          .collection('groups')
          .doc(widget.groupId)
          .collection('pokes')
          .add({
        'targetUid': widget.targetUid,
        'targetName': widget.targetName,
        'fromName': fromName,
        'fromUid': fromUid,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      if (mounted) setState(() {
        _sent = true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          if (_sent) ...[
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.accent, size: 52),
            const SizedBox(height: 14),
            Text(
              'Poke sent!',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.targetName} has been poked 👆',
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ] else ...[
            Text(
              'Poke ${widget.targetName}?',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This will send a notification saying\n"${widget.targetName}, put the phone down!"',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            LoadingOverlay(
              isLoading: _loading,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _sendPoke(context),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentOrange),
                      child: const Text('Poke! 👆'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Small Shared Widgets ─────────────────────────────────────────────────────
class _AppUsageRow extends StatelessWidget {
  final String appName;
  final int minutes;
  final double percentage;

  const _AppUsageRow({
    required this.appName,
    required this.minutes,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                appName.isNotEmpty ? appName[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentOrange,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        appName,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      ScreentimeService.formatMinutes(minutes),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: AppTheme.surfaceHighlight,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.accentOrange),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySummaryTile extends StatelessWidget {
  final ScreentimeModel model;

  const _DaySummaryTile({required this.model});

  @override
  Widget build(BuildContext context) {
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayName = days[model.date.weekday];

    return GradientCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surfaceHighlight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${model.date.day}',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  dayName,
                  style: GoogleFonts.inter(
                      fontSize: 10, color: AppTheme.textHint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ScreentimeService.formatMinutes(model.totalMinutes),
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentOrange,
              ),
            ),
          ),

        ],
      ),
    );
  }
}

class _WeekBarChart extends StatelessWidget {
  final List<ScreentimeModel> data;

  const _WeekBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final maxMinutes =
        data.map((d) => d.totalMinutes).reduce((a, b) => a > b ? a : b);

    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return GradientCard(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.map((s) {
            final frac =
                maxMinutes > 0 ? s.totalMinutes / maxMinutes : 0.0;
            final dayLabel = days[s.date.weekday];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      ScreentimeService.formatMinutes(s.totalMinutes),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: AppTheme.textHint,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: (frac * 72).clamp(4.0, 72.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.accentOrange,
                            AppTheme.accentOrange.withOpacity(0.5)
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dayLabel,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
