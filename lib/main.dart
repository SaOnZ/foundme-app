import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/verify_email_page.dart';
import 'pages/forgot_password_page.dart';
import 'pages/home_page.dart';
import 'services/navigation_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    if (e.toString().contains('[core/duplicate-app]')) {
      // Firebase already initialized, proceed.
    } else {
      rethrow;
    }
  }
  try {
    await dotenv.load(fileName: ".env");
    print("✅ .env loaded successfully!");
    print("🔍 Keys found: ${dotenv.env.keys}"); // This will list valid keys
    print(
      "🔍 GEMINI Key: ${dotenv.env['GEMINI_API_KEY']}",
    ); // Should print the key
    await AuthService.instance.saveUserToken();
  } catch (e) {
    print("❌ Failed to load .env: $e");
  }

  await NotificationService.instance.init();

  runApp(const FoundMeApp());
}

class FoundMeApp extends StatelessWidget {
  const FoundMeApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'FoundMe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      initialRoute: '/',
      routes: {
        '/': (_) => const AuthGate(),
        '/login': (_) => const LoginPage(),
        '/register': (_) => const RegisterPage(),
        '/verify': (_) => const VerifyEmailPage(),
        '/forgot': (_) => const ForgotPasswordPage(),
        '/home': (_) => const HomePage(),
      },
    );
  }
}

/// Listens to auth state and routes to the right screen.
/// If logged in but not email-verified, redirect to verify page.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService.instance.authState(),
      builder: (context, snapshot) {
        final user = AuthService.instance.currentUser;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (user == null) {
          return const LoginPage();
        }
        if (user.emailVerified) {
          return const HomePage();
        }
        return const VerifyEmailPage();
      },
    );
  }
}
