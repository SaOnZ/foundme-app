import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  String? _emailV(String? v) => (v == null || v.isEmpty || !v.contains('@'))
      ? 'Enter a valid email'
      : null;
  String? _passV(String? v) =>
      (v == null || v.length < 8) ? 'Min 8 characters' : null;

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text("Attention"),
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
    // 1. Check for empty fields FIRST
    if (_email.text.isEmpty || _pass.text.isEmpty) {
      _showErrorDialog("Please fill out all fields!");
      return;
    }

    // 2. Standard validation
    if (!_form.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await AuthService.instance.login(
        email: _email.text,
        password: _pass.text,
      );

      // Route through AuthGate, which is the single source of truth for
      // where a signed-in user belongs (admin / matric verification /
      // email verification / home). This also enforces the email-verification
      // and matric gates that a direct push to /home would bypass.
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      }
    } on FirebaseAuthException catch (e) {
      // Switch on the typed error code. Modern Firebase Auth (with email
      // enumeration protection) returns 'invalid-credential' for both a wrong
      // password and an unknown email, so the old wrong-password/user-not-found
      // string matching was effectively dead.
      String errorMessage;
      switch (e.code) {
        case 'invalid-email':
          errorMessage = "That email address doesn't look right.";
          break;
        case 'user-disabled':
          errorMessage = "This account has been disabled.";
          break;
        case 'too-many-requests':
          errorMessage = "Too many attempts. Please try again later.";
          break;
        case 'network-request-failed':
          errorMessage = "Network error. Check your connection and try again.";
          break;
        default:
          errorMessage = "Invalid credentials. Please check your details.";
      }

      if (mounted) {
        _showErrorDialog(errorMessage);
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog("An unexpected error occurred. Please try again.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() => _loading = true);
    try {
      await AuthService.instance.continueAsGuest();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    } catch (_) {
      if (mounted) {
        _showErrorDialog("Guest sign-in failed. Please try again.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final user = await AuthService.instance.signInWithGoogle();
      if (!mounted) return;
      if (user == null) {
        // Null means the user dismissed the Google account picker — not an
        // error, so stay quiet.
        return;
      }
      // Signed in: AuthGate reacts to the auth stream and routes us onward.
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    } catch (_) {
      if (mounted) {
        _showErrorDialog(
          "Google sign-in failed. Please check your connection and try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext content) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 60,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'FoundMe',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Find what matters.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 30),

                  TextFormField(
                    controller: _email,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    validator: _emailV,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _pass,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    obscureText: _obscure,
                    validator: _passV,
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
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/forgot'),
                      child: const Text('Forgot Password?'),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Login button
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
                          : const Text('Login', style: TextStyle(fontSize: 16)),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text("OR"),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ===========================================================
                  // ↓↓↓↓↓ UPGRADE: GOOGLE & GUEST (Secondary Actions) ↓↓↓↓↓
                  // ===========================================================
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                        height: 24,
                        errorBuilder: (ctx, _, __) => const Icon(Icons.public),
                      ),
                      label: const Text('Sign in with Google'),
                      onPressed: _loading ? null : _signInWithGoogle,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: _loading ? null : _continueAsGuest,
                    child: const Text(
                      'Continue as Guest',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ===========================================================
                  //     UPGRADE: SIGN UP (Moved to bottom)
                  // ===========================================================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?"),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/register'),
                        child: const Text(
                          'Sign Up',
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
