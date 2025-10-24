// auth_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _users = FirebaseFirestore.instance.collection('users');

  //Streams / getters
  Stream<User?> authState() => _auth.authStateChanges();
  Stream<User?> idTokenStream() => _auth.idTokenChanges();
  User? get currentUser => _auth.currentUser;

  ///Guest= not signed in OR anonymous sign-in.
  bool get isGuest =>
      _auth.currentUser == null || (_auth.currentUser?.isAnonymous ?? false);

  /// Read custom claims (currently we only need 'admin' : true/false)
  Future<Map<String, bool>> roles() async {
    final u = _auth.currentUser;
    if (u == null) return {'admin': false};
    final res = await u.getIdTokenResult(true); //force refresh
    final c = res.claims ?? {};
    return {'admin': c['admin'] == true};
  }

  Future<void> refreshClaims() async {
    final u = _auth.currentUser;
    if (u != null) await u.getIdToken(true);
  }

  Stream<UserModel?> userStream() {
    final u = currentUser;
    if (u == null) return Stream.value(null);
    return _users.doc(u.uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromDoc(doc);
    });
  }

  /*-------------Auth actions----------------*/

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user!.updateDisplayName(name.trim());
    await cred.user!.reload(); //ensure displayName is set

    //create user doc
    await _users.doc(cred.user!.uid).set({
      'name': name.trim(),
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'role': 'user',
      'fcmTokens': [],
    }, SetOptions(merge: true));

    await cred.user!.sendEmailVerification();
  }

  Future<void> login({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    //make sure a users doc exists (older accounts or imports)
    final u = _auth.currentUser!;
    final doc = await _users.doc(u.uid).get();
    if (!doc.exists) {
      await _users.doc(u.uid).set({
        'name': u.displayName ?? '',
        'email': u.email ?? email.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'user',
        'fcmTokens': [],
      }, SetOptions(merge: true));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> resendVerificationEmail() async {
    final u = _auth.currentUser;
    if (u != null && !u.emailVerified) {
      await u.sendEmailVerification();
    }
  }

  Future<bool> checkEmailVerified() async {
    final u = _auth.currentUser;
    if (u == null) return false;
    await u.reload();
    return _auth.currentUser!.emailVerified;
  }

  Future<void> updateDisplayName(String name) async {
    final u = _auth.currentUser;
    if (u == null) return;
    await u.updateDisplayName(name.trim());
    await _users.doc(u.uid).set({'name': name.trim()}, SetOptions(merge: true));
  }

  // ignore: unused_element
  Future<void> logout() async {
    await _auth.signOut();
  }

  /*-------------Guest / upgrade flow ----------------*/

  ///sign in anonymously (guest browsing).
  Future<void> continueAsGuest() async {
    await _auth.signInAnonymously();
  }

  /// Convert the current anonymous user into a real email user (keeps data).
  Future<void> upgradeGuestToEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw FirebaseAuthException(
        code: 'not-anonymous',
        message: 'Not a guest user.',
      );
    }

    // Link email/password to the anonymous account
    final cred = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );

    await user.linkWithCredential(cred);
    await user.updateDisplayName(name.trim());
    await user.getIdToken(true);

    await _users.doc(user.uid).set({
      'name': name.trim(),
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'role': 'user',
    }, SetOptions(merge: true));

    await user.sendEmailVerification();
  }
}
