import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  String? _v(String? v) =>
      (v == null || !_emailRe.hasMatch(v.trim()))
      ? 'Enter a valid email'
      : null;

  // Same neutral confirmation whether or not the email is registered, so the
  // screen never reveals which addresses have accounts (account enumeration).
  static const _neutralMessage =
      'If an account exists for that email, a reset link has been sent.';

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await AuthService.instance.sendPasswordReset(_email.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(_neutralMessage)));
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // 'user-not-found' must look identical to success; only surface genuine
      // failures the user can act on (network / rate limiting).
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(_neutralMessage)));
        Navigator.pop(context);
      } else if (e.code == 'too-many-requests') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Too many attempts. Try again later.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: _v,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const CircularProgressIndicator()
                        : const Text('Send reset link'),
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
