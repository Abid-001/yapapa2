import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Shows a one-time screen explaining why Usage Access permission is needed.
/// After granting, user is sent to Android's Usage Access settings page.
class UsagePermissionScreen extends StatefulWidget {
  final VoidCallback onDone;

  const UsagePermissionScreen({super.key, required this.onDone});

  @override
  State<UsagePermissionScreen> createState() =>
      _UsagePermissionScreenState();
}

class _UsagePermissionScreenState
    extends State<UsagePermissionScreen> {
  static const _platform =
      MethodChannel('com.yapapa.app/usage_permission');

  Future<void> _openUsageSettings() async {
    try {
      await _platform.invokeMethod('openUsageSettings');
    } catch (_) {
      // Fallback: just mark as done and continue
    }
    // Mark as shown so we don't show again
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('usage_permission_shown', true);
    if (mounted) widget.onDone();
  }

  Future<void> _skipForNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('usage_permission_shown', true);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.phone_android_rounded,
                  size: 40,
                  color: AppTheme.accentOrange,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Enable Screentime Tracking',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Yapapa needs Usage Access permission to track your daily screentime and compare it with your friends on the leaderboard.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _StepCard(
                number: '1',
                text: 'Tap "Open Settings" below',
              ),
              const SizedBox(height: 10),
              _StepCard(
                number: '2',
                text: 'Find "Yapapa" in the list',
              ),
              const SizedBox(height: 10),
              _StepCard(
                number: '3',
                text: 'Toggle it ON',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openUsageSettings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('Open Settings'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _skipForNow,
                  child: Text(
                    'Skip for now (screentime won\'t work)',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textHint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number;
  final String text;

  const _StepCard({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.accentOrange.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentOrange,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Call this on app start to check if we need to show the permission screen
Future<bool> shouldShowUsagePermission() async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool('usage_permission_shown') ?? false);
}
