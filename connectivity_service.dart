import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class UsagePermissionScreen extends StatefulWidget {
  final VoidCallback onContinue;
  const UsagePermissionScreen({super.key, required this.onContinue});
  @override
  State<UsagePermissionScreen> createState() => _UsagePermissionScreenState();
}

/// Uses WidgetsBindingObserver so when the user comes back from the
/// Android Usage Access Settings screen the app automatically continues.
class _UsagePermissionScreenState extends State<UsagePermissionScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.yapapa.app/platform');
  bool _waitingForReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Fires when the user returns to the app (e.g. from Settings).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_waitingForReturn && state == AppLifecycleState.resumed) {
      _waitingForReturn = false;
      _done();
    }
  }

  Future<void> _openSettings() async {
    try {
      // Calls MainActivity.kt which fires ACTION_USAGE_ACCESS_SETTINGS
      await _channel.invokeMethod('openUsageSettings');
      setState(() => _waitingForReturn = true);
      // App stays on this screen until user returns from Settings
    } catch (_) {
      // Channel not wired up — fall through
      await _done();
    }
  }

  Future<void> _done() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('usage_permission_shown', true);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_android, size: 80, color: AppTheme.primary),
              const SizedBox(height: 32),
              Text(
                'Enable Screen Time Tracking',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Yapapa needs Usage Access permission to track your screen time and share it with your group.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              const _Step(number: '1', text: 'Tap "Open Settings" below'),
              const _Step(number: '2', text: 'Find "Yapapa" in the list'),
              const _Step(number: '3', text: 'Toggle it ON'),
              const _Step(number: '4', text: 'Press back — app continues automatically'),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Open Settings',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _done,
                child: const Text(
                  'Skip for now',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.primary),
          ),
          child: Center(
            child: Text(number,
                style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
        ),
      ]),
    );
  }
}
