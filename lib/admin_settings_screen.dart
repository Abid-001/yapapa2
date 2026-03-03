import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';
import 'budget_screen.dart';
import 'screentime_screen.dart';
import 'leaderboard_screen.dart';
import 'chat_screen.dart';
import 'preset_notification_sheet.dart';
import 'admin_settings_screen.dart';
import '../widgets/common_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _notifCount = 0;
  late final List<Widget> _screens;

  void _switchTab(int idx) {
    setState(() => _currentIndex = idx);
    NotificationService.isInChatScreen = (idx == 1);
  }

  final List<String> _titles = [
    'Home',
    'Chat',
  ];

  final List<IconData> _icons = [
    Icons.home_rounded,
    Icons.chat_bubble_outline_rounded,
  ];

  void _showBudgetModal() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text('Budget', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
      body: const BudgetScreen(),
    )));
  }

  void _showScreentimeModal() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text('Screentime', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
      body: const ScreentimeScreen(),
    )));
  }

  void _showLeaderboardModal() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text('Leaderboard', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
      body: const LeaderboardScreen(),
    )));
  }

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(
        onGoToChat: () => _switchTab(1),
        onGoToBudget: _showBudgetModal,
        onGoToScreentime: _showScreentimeModal,
        onGoToLeaderboard: _showLeaderboardModal,
      ),
      const ChatScreen(),
    ];
    _loadNotifCount();
    // Listen to unread count from ChatScreen
    chatUnreadCount.addListener(() { if (mounted) setState(() {}); });
  }

  Future<void> _loadNotifCount() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('inbox_notifications') ?? [];
    if (mounted) setState(() => _notifCount = saved.length);
  }

  void _showNotificationsInbox() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('inbox_notifications') ?? [];
    final notifs = saved
        .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
        .toList()
        .reversed
        .toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NotificationsInbox(
        notifications: notifs,
        onClear: () async {
          await prefs.remove('inbox_notifications');
          if (mounted) setState(() => _notifCount = 0);
        },
      ),
    );
    // Mark as read
    await prefs.setStringList('inbox_notifications_read', saved);
    if (mounted) setState(() => _notifCount = 0);
  }

  void _showPresetSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PresetNotificationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_currentIndex != 0) {
          // Not on home → go to home
          setState(() => _currentIndex = 0);
        } else {
          // Already on home → exit app
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        // appBar kept unchanged
        title: Text(
          _titles[_currentIndex],
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          // Settings icon
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AdminSettingsScreen()),
            ),
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.settings_outlined,
                size: 20,
                color: AppTheme.textPrimary,
              ),
            ),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (_currentIndex == 0 && v < -300) _switchTab(1);
          else if (_currentIndex == 1 && v > 300) _switchTab(0);
        },
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            // Offline banner shown at top of every screen
            _OfflineDetector(),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: AppTheme.divider, width: 1),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 46,
            child: Row(
              children: List.generate(_screens.length, (i) {
                final selected = _currentIndex == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _switchTab(i),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.primary.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Stack(clipBehavior: Clip.none, children: [
                              Icon(
                                _icons[i],
                                size: 22,
                                color: selected ? AppTheme.primary : AppTheme.textHint,
                              ),
                              // Unread dot for chat tab (index 1)
                              if (i == 1 && !selected && chatUnreadCount.value > 0)
                                Positioned(
                                  top: -3, right: -3,
                                  child: Container(
                                    width: 8, height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF00A884),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _titles[i],
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    ),  // PopScope
    );
  }
}

class _OfflineDetector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isOffline = context.watch<ConnectivityService>().isOffline;
    return OfflineBanner(isOffline: isOffline);
  }
}

// ── Notifications Inbox ────────────────────────────────────────────────────────
class _NotificationsInbox extends StatelessWidget {
  final List<Map<String, dynamic>> notifications;
  final VoidCallback onClear;

  const _NotificationsInbox(
      {required this.notifications, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Notifications',
                  style: GoogleFonts.inter(
                      fontSize: 17, fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              if (notifications.isNotEmpty)
                TextButton(
                  onPressed: () {
                    onClear();
                    Navigator.pop(context);
                  },
                  child: Text('Clear all',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppTheme.error)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (notifications.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const Icon(Icons.notifications_none_rounded,
                      size: 48, color: AppTheme.textHint),
                  const SizedBox(height: 12),
                  Text('No notifications yet',
                      style: GoogleFonts.inter(
                          fontSize: 14, color: AppTheme.textHint)),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: notifications.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: AppTheme.divider, height: 1),
                itemBuilder: (context, i) {
                  final n = notifications[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.notifications_rounded,
                                size: 18, color: AppTheme.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n['senderName'] ?? 'Someone',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                n['text'] ?? '',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
