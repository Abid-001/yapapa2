import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import 'home_screen.dart';
import 'budget_screen.dart';
import 'screentime_screen.dart';
import 'leaderboard_screen.dart';
import 'chat_screen.dart';
import 'preset_notification_sheet.dart';
import 'admin_settings_screen.dart';
import '../widgets/common_widgets.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    BudgetScreen(),
    ScreentimeScreen(),
    LeaderboardScreen(),
    ChatScreen(),
  ];

  final List<String> _titles = [
    'Home',
    'Budget',
    'Screentime',
    'Leaderboard',
    'Chat',
  ];

  final List<IconData> _icons = [
    Icons.home_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.phone_android_rounded,
    Icons.leaderboard_rounded,
    Icons.chat_bubble_outline_rounded,
  ];

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

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          // Bell icon for preset notifications
          IconButton(
            onPressed: _showPresetSheet,
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.notifications_outlined,
                size: 20,
                color: AppTheme.textPrimary,
              ),
            ),
            tooltip: 'Send Notification',
          ),
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
      body: Column(
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: AppTheme.divider, width: 1),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              children: List.generate(_screens.length, (i) {
                final selected = _currentIndex == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentIndex = i),
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
                            child: Icon(
                              _icons[i],
                              size: 22,
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textHint,
                            ),
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
