import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _checking = false;
  bool _canResend = true;
  bool _loggingOut = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final ok = await AuthService.instance.checkEmailVerified();
      if (!mounted) return;
      if (ok) {
        // Route back through AuthGate so it can send the user to the next
        // required step (matric verification) or home, rather than skipping
        // straight to /home.
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not verified yet. Refresh after you click the email link',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    if (!_canResend) return;
    try {
      await AuthService.instance.resendVerificationEmail();
      if (!mounted) return;
      setState(() => _canResend = false);
      _timer = Timer(const Duration(seconds: 30), () {
        if (mounted) setState(() => _canResend = true);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent again.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send the email. Please try again shortly.'),
        ),
      );
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await AuthService.instance.logout();
      // AuthGate reacts to the auth stream and routes back to login.
    } catch (_) {
      if (!mounted) return;
      setState(() => _loggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logout failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'We sent a verification link to:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Click the link in your email, then tap the button below.',
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _checking ? null : _check,
                  child: _checking
                      ? const CircularProgressIndicator()
                      : const Text('I have verified - continue'),
                ),
                TextButton(
                  onPressed: _canResend ? _resend : null,
                  child: Text(
                    _canResend ? 'Resend Verification email' : 'Wait 30s...',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loggingOut ? null : _logout,
                  child: const Text('Logout'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
