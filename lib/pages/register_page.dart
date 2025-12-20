// ignore_for_file: unused_element, unused_field, prefer_final_fields

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _nameV(String? v) =>
      (v == null || v.trim().length < 2) ? 'Enter your name' : null;
  String? _emailV(String? v) =>
      (v == null || !v.contains('@')) ? 'Enter a valid email' : null;
  String? _passV(String? v) {
    if (v == null || v.length < 8) return 'Min 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Include letters and numbers';
    }
    return null;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Colors.blueAccent,
              size: 28,
            ),
            SizedBox(width: 10),
            Text("Registration"),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_name.text.isEmpty || _email.text.isEmpty || _pass.text.isEmpty) {
      _showErrorDialog("Please fill out all fields.");
      return;
    }

    if (_pass.text != _confirm.text) {
      _showErrorDialog("Password do not match.");
      return;
    }

    if (!_form.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final auth = AuthService.instance;
      if (auth.isGuest) {
        await auth.upgradeGuestToEmail(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _pass.text,
        );
      } else {
        await auth.register(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _pass.text,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification email. Please check you inbox.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/verify', (_) => false);
    } on Exception catch (e) {
      if (!mounted) return;

      String msg = 'Registration failed.';
      if (e.toString().contains('email-already-in-use')) {
        msg = 'That email is already registered.';
      } else if (e.toString().contains('invalid-email')) {
        msg = 'That email address is invalid.';
      } else if (e.toString().contains('weak-password')) {
        msg = 'The password provided is too weak.';
      }

      _showErrorDialog(msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ==================================================================
      //          TRANSPARENT APP BAR (Cleaner Look)
      // ==================================================================
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            // Added scroll for smaller screens
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, // Align text left
                children: [
                  // ===========================================================
                  //        HEADER SECTION
                  // ===========================================================
                  const Text(
                    "Create Account",
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "Join us to start finding items.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 30),

                  // ===========================================================
                  //        MODERN INPUT FIELDS (Icons + Borders)
                  // ===========================================================

                  // Full Name
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: _nameV,
                  ),
                  const SizedBox(height: 16),

                  // Email
                  TextFormField(
                    controller: _email,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: _emailV,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _pass,
                    textInputAction: TextInputAction.next,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: _passV,
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password
                  TextFormField(
                    controller: _confirm,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(), // Submit on Enter
                    obscureText: _obscure, // Matches the password visibility
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Please confirm your password'
                        : null,
                  ),

                  const SizedBox(height: 30),

                  // ===========================================================
                  //        BIGGER BUTTON & LOGIN LINK
                  // ===========================================================
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Register',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Login Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Already have an account?"),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context), // Go back to Login
                        child: const Text(
                          'Login',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
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
