import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../theme/app_theme.dart';

class MemberProfileScreen extends StatelessWidget {
  final UserModel member;
  const MemberProfileScreen({super.key, required this.member});

  Future<void> _makeCall(BuildContext context) async {
    final number = member.phoneNumber.trim();
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This member has no phone number saved.')),
      );
      return;
    }
    // Use android.intent.action.DIAL — opens dialer with number pre-filled
    // without requiring CALL_PHONE permission to be granted at runtime
    final uri = Uri(scheme: 'tel', path: number);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open phone app: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = member.username.isNotEmpty
        ? member.username[0].toUpperCase()
        : '?';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Profile',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            // Avatar
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(initials,
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            Text(member.username,
                style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            if (member.isAdmin) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                ),
                child: Text('Admin',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 32),
            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppTheme.divider.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.phone_rounded,
                    label: 'Phone',
                    value: member.phoneNumber.isEmpty
                        ? 'Not provided'
                        : member.phoneNumber,
                  ),
                  const Divider(color: AppTheme.divider, height: 24),
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Joined',
                    value: _formatDate(member.joinedAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            // Call button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: member.phoneNumber.isEmpty
                    ? null
                    : () => _makeCall(context),
                icon: const Icon(Icons.call_rounded, color: Colors.white),
                label: Text(
                  member.phoneNumber.isEmpty
                      ? 'No Phone Number'
                      : 'Call ${member.username}',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: member.phoneNumber.isEmpty
                      ? AppTheme.surfaceHighlight
                      : const Color(0xFF2ECC71),
                  disabledBackgroundColor: AppTheme.surfaceHighlight,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 12),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppTheme.textSecondary)),
        const Spacer(),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
      ],
    );
  }
}
