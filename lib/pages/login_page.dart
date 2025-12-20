import 'package:flutter/material.dart';
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

  Future<void> _submit() async {
    if (_email.text.isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pease fill out all fields!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.login(
        email: _email.text,
        password: _pass.text,
      );
      if (mounted) Navigator.pushReplacementNamed(context, '/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Login failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() => _loading = true);
    try {
      await AuthService.instance.continueAsGuest();
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Guest sign-infailed: $e')));
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
                    size: 64,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'FoundMe',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Find what matters.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 24),

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
                  const SizedBox(height: 12),
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
                      onPressed: _loading
                          ? null
                          : () async {
                              setState(() => _loading = true);

                              final user = await AuthService.instance
                                  .signInWithGoogle();

                              setState(() => _loading = false);

                              if (user != null) {
                                // AuthGate handles navigation automatically,
                                // but we can pop here just in case or show success
                                if (mounted) {
                                  // No explicit navigation needed if using AuthGate stream
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Google Sign-In canceled or failed',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
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

                  // ===========================================================
                  //     UPGRADE: SIGN UP (Moved to bottom)
                  // ===========================================================
                  // Create account
                  const SizedBox(height: 20),
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
