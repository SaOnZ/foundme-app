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
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
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
    await AuthService.instance.resendVerificationEmail();
    setState(() => _canResend = false);
    _timer = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _canResend = true);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verification email sent again.')),
    );
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
                  onPressed: () => AuthService.instance.logout(),
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
