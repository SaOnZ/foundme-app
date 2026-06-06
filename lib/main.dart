import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/verify_email_page.dart';
import 'pages/forgot_password_page.dart';
import 'pages/home_page.dart';
import 'services/navigation_service.dart';
import 'services/notification_service.dart';
import "package:cloud_firestore/cloud_firestore.dart";
import 'pages/matric_verification_page.dart';
import 'pages/admin_dashboard_page.dart';

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
        '/': (context) => const AuthGate(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/verify': (context) => const VerifyEmailPage(),
        '/forgot': (context) => const ForgotPasswordPage(),
        '/home': (context) => const HomePage(),
        '/admin': (context) => const AdminDashboardPage(),
      },
    );
  }
}

/// Listens to auth state and routes to the right screen.
///
/// This is the single source of truth for top-level routing. The order of
/// gates is intentional:
///   not signed in        -> LoginPage
///   anonymous (guest)    -> HomePage      (guests have no Firestore user doc)
///   email not verified   -> VerifyEmailPage
///   user doc not ready   -> loading       (don't guess a destination)
///   role == admin        -> AdminDashboardPage
///   matric not verified  -> MatricVerificationPage
///   otherwise            -> HomePage
///
/// It listens to [idTokenStream] (not just authState) so that a forced token
/// refresh after the user verifies their email re-emits and re-routes here.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static const _loading = Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.idTokenStream(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loading;
        }

        final user = snapshot.data;

        // Not logged in
        if (user == null) {
          return const LoginPage();
        }

        // Guests browse straight to home; they intentionally have no user doc.
        if (user.isAnonymous) {
          return const HomePage();
        }

        // Email users must verify their email before anything else.
        if (!user.emailVerified) {
          return const VerifyEmailPage();
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnap) {
            // Still loading the user doc.
            if (userSnap.connectionState == ConnectionState.waiting) {
              return _loading;
            }

            // The doc may not exist yet for a brand-new account: the auth
            // state fires before (or independently of) the Firestore write.
            // Wait rather than defaulting to the wrong screen (which would
            // strand new users on the matric page).
            if (!userSnap.hasData || !(userSnap.data?.exists ?? false)) {
              return _loading;
            }

            final userData = userSnap.data!.data() as Map<String, dynamic>?;

            final role = userData?['role'] ?? 'user';
            // Check the 'isVerified' flag (matric verification)
            final isVerified = userData?['isVerified'] ?? false;

            if (role == 'admin') {
              return const AdminDashboardPage();
            }

            // For normal users, check Matric Verification
            if (!isVerified) {
              return const MatricVerificationPage();
            }

            return const HomePage();
          },
        );
      },
    );
  }
}
