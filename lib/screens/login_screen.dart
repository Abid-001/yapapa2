import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

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
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: LoadingOverlay(
          isLoading: _isLoading,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 48),
                  // Logo
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 28,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Y',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'YAPAPA',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your accountability circle',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Tab Bar
                  Container(
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
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
                      tabs: const [
                        Tab(text: 'Login'),
                        Tab(text: 'Create'),
                        Tab(text: 'Join'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tab Views — fixed height to avoid overflow
                  SizedBox(
                    height: 520,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _LoginForm(onLoading: (v) => setState(() => _isLoading = v)),
                        _CreateGroupForm(onLoading: (v) => setState(() => _isLoading = v)),
                        _JoinGroupForm(onLoading: (v) => setState(() => _isLoading = v)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Login Form ───────────────────────────────────────────────────────────────
class _LoginForm extends StatefulWidget {
  final void Function(bool) onLoading;

  const _LoginForm({required this.onLoading});

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _usernameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String _pin = '';
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final username = _usernameCtrl.text.trim();
    final inviteCode = _codeCtrl.text.trim().toUpperCase();

    if (username.isEmpty) {
      setState(() => _error = 'Please enter your username.');
      return;
    }
    if (inviteCode.length != 6) {
      setState(() => _error = 'Please enter your 6-character group invite code.');
      return;
    }
    if (_pin.length != 4) {
      setState(() => _error = 'Please enter your 4-digit PIN.');
      return;
    }

    widget.onLoading(true);
    final auth = context.read<AuthService>();
    final err = await auth.loginWithPin(
      username: username,
      pin: _pin,
      inviteCode: inviteCode,
    );
    if (mounted) {
      widget.onLoading(false);
      if (err != null) setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('Group Invite Code'),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            decoration: const InputDecoration(
              hintText: 'e.g. AB3XY7',
              prefixIcon: Icon(Icons.group_outlined),
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              LengthLimitingTextInputFormatter(6),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            ],
          ),
          const SizedBox(height: 16),
          _buildLabel('Username'),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              hintText: 'Your username',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          _buildLabel('PIN'),
          const SizedBox(height: 12),
          PinInput(onChanged: (v) => _pin = v),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorBox(_error!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text('Login'),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Enter the invite code shown on your group\'s home screen.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Create Group Form ────────────────────────────────────────────────────────
class _CreateGroupForm extends StatefulWidget {
  final void Function(bool) onLoading;

  const _CreateGroupForm({required this.onLoading});

  @override
  State<_CreateGroupForm> createState() => _CreateGroupFormState();
}

class _CreateGroupFormState extends State<_CreateGroupForm> {
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _pin = '';
  String _confirmPin = '';
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final username = _usernameCtrl.text.trim();

    if (username.isEmpty) {
      setState(() => _error = 'Please enter a username.');
      return;
    }
    if (username.length < 2) {
      setState(() => _error = 'Username must be at least 2 characters.');
      return;
    }
    if (_pin.length != 4) {
      setState(() => _error = 'Please enter a 4-digit PIN.');
      return;
    }
    if (_pin != _confirmPin) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your phone number.');
      return;
    }

    widget.onLoading(true);
    final auth = context.read<AuthService>();
    final err = await auth.createGroup(username: username, pin: _pin, phoneNumber: _phoneCtrl.text.trim());
    if (mounted) {
      widget.onLoading(false);
      if (err != null) setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('Your Username'),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              hintText: 'Choose a username',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          _buildLabel('Phone Number'),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              hintText: '+880 1XX XXX XXXX',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _buildLabel('Set PIN'),
          const SizedBox(height: 12),
          PinInput(onChanged: (v) => _pin = v),
          const SizedBox(height: 16),
          _buildLabel('Confirm PIN'),
          const SizedBox(height: 12),
          PinInput(onChanged: (v) => _confirmPin = v),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorBox(_error!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text('Create Group'),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'You will become the group admin.\nShare your invite code with friends!',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Join Group Form ──────────────────────────────────────────────────────────
class _JoinGroupForm extends StatefulWidget {
  final void Function(bool) onLoading;

  const _JoinGroupForm({required this.onLoading});

  @override
  State<_JoinGroupForm> createState() => _JoinGroupFormState();
}

class _JoinGroupFormState extends State<_JoinGroupForm> {
  final _usernameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _pin = '';
  String _confirmPin = '';
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final username = _usernameCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();

    if (username.isEmpty) {
      setState(() => _error = 'Please enter a username.');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = 'Please enter the 6-character invite code.');
      return;
    }
    if (_pin.length != 4) {
      setState(() => _error = 'Please enter a 4-digit PIN.');
      return;
    }
    if (_pin != _confirmPin) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your phone number.');
      return;
    }

    widget.onLoading(true);
    final auth = context.read<AuthService>();
    final err = await auth.joinGroup(
      username: username,
      pin: _pin,
      inviteCode: code,
      phoneNumber: _phoneCtrl.text.trim(),
    );
    if (mounted) {
      widget.onLoading(false);
      if (err != null) setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('Your Username'),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              hintText: 'Choose a username',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          _buildLabel('Group Invite Code'),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            decoration: const InputDecoration(
              hintText: 'e.g. AB3XY7',
              prefixIcon: Icon(Icons.group_outlined),
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              LengthLimitingTextInputFormatter(6),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            ],
          ),
          const SizedBox(height: 16),
          _buildLabel('Phone Number'),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              hintText: '+880 1XX XXX XXXX',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _buildLabel('Set PIN'),
          const SizedBox(height: 12),
          PinInput(onChanged: (v) => _pin = v),
          const SizedBox(height: 16),
          _buildLabel('Confirm PIN'),
          const SizedBox(height: 12),
          PinInput(onChanged: (v) => _confirmPin = v),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorBox(_error!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text('Join Group'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────
Widget _buildLabel(String text) {
  return Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppTheme.textSecondary,
      letterSpacing: 0.3,
    ),
  );
}

Widget _errorBox(String message) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.error.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.error.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 16, color: AppTheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.error,
            ),
          ),
        ),
      ],
    ),
  );
}
