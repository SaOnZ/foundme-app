// auth_service.dart
import 'dart:io'; // For File
import 'package:firebase_storage/firebase_storage.dart'; //For Storage
import 'package:image_picker/image_picker.dart'; // For Image Picker
import 'package:mime/mime.dart'; // For lookupMime Type
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'notification_service.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _users = FirebaseFirestore.instance.collection('users');
  final _storage = FirebaseStorage.instance;

  //Streams / getters
  Stream<User?> authState() => _auth.authStateChanges();
  Stream<User?> idTokenStream() => _auth.idTokenChanges();
  User? get currentUser => _auth.currentUser;

  ///Guest= not signed in OR anonymous sign-in.
  bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

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

  Stream<UserModel?> userStream({String? uid}) {
    // 1. Add optional param
    // 2. Use the provided uid, or fallback to the current user
    final u = uid ?? currentUser?.uid;

    if (u == null) return Stream.value(null);
    return _users.doc(u).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromDoc(doc);
    });
  }

  // One-shot profile cache for list rows. Avoids a realtime listener per row.
  final Map<String, Future<UserModel?>> _profileCache = {};

  /// Memoized variant of [getUserProfile] for use in list builders, so a name
  /// lookup isn't refetched on every rebuild.
  Future<UserModel?> getUserProfileCached(String uid) {
    return _profileCache.putIfAbsent(uid, () => getUserProfile(uid));
  }

  /// Fetches a user's profile data once from Firestore.
  Future<UserModel?> getUserProfile(String uid) async {
    try {
      final doc = await _users.doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromDoc(doc);
    } catch (e) {
      return null;
    }
  }

  // Bounded so the admin "Users" view can't download the entire users
  // collection. (Follow-up: add search + startAfter pagination.)
  Stream<List<UserModel>> adminGetAllUsers({int limit = 200}) {
    return _users
        .orderBy('name')
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(UserModel.fromDoc).toList());
  }

  /*-------------Auth actions----------------*/

  /// The canonical shape of a freshly-created user document. All signup paths
  /// (email, Google, guest upgrade, legacy login backfill) go through this so
  /// the schema stays consistent (previously the email and Google paths wrote
  /// different field sets).
  Map<String, dynamic> _newUserDoc({
    required String name,
    required String email,
    String? photoURL,
  }) => {
    'name': name,
    'email': email,
    'photoURL': photoURL,
    'role': 'user',
    'createdAt': FieldValue.serverTimestamp(),
    'fcmTokens': <String>[],
    'ratingCount': 0,
    'averageRating': 0.0,
  };

  /// Creates the user's Firestore doc if it doesn't already exist. Safe to call
  /// on every sign-in; never overwrites an existing profile.
  Future<void> _ensureUserDoc(
    User user, {
    String? name,
    String? email,
    String? photoURL,
  }) async {
    final ref = _users.doc(user.uid);
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set(
      _newUserDoc(
        name: name ?? user.displayName ?? '',
        email: email ?? user.email ?? '',
        photoURL: photoURL ?? user.photoURL,
      ),
      SetOptions(merge: true),
    );
  }

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

    await _ensureUserDoc(cred.user!, name: name.trim(), email: email.trim());

    await cred.user!.sendEmailVerification();
  }

  Future<void> login({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    //make sure a users doc exists (older accounts or imports)
    await _ensureUserDoc(_auth.currentUser!, email: email.trim());
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
    final verified = _auth.currentUser?.emailVerified ?? false;
    if (verified) {
      // Force an ID-token refresh so AuthGate's idTokenChanges stream re-emits
      // with the updated emailVerified flag and re-routes the user.
      await _auth.currentUser?.getIdToken(true);
    }
    return verified;
  }

  Future<void> updateDisplayName(String name) async {
    final u = _auth.currentUser;
    if (u == null) return;
    await u.updateDisplayName(name.trim());
    await _users.doc(u.uid).set({'name': name.trim()}, SetOptions(merge: true));
  }

  // Upload default profile picture
  Future<void> updateProfilePicture(XFile imageFile) async {
    final u = _auth.currentUser;
    if (u == null) return; // Not logged in

    try {
      final file = File(imageFile.path);
      final contentType = lookupMimeType(imageFile.path) ?? 'image/jpeg';

      // 1. Define storage path (profile_pictures/USER_ID/profile.jpg)
      final ref = _storage.ref('profile_pictures/${u.uid}/profile.jpg');

      // 2. Upload the file
      final task = await ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );

      // 3. Get the download URL
      final url = await task.ref.getDownloadURL();

      // 4. Save the URL to the user's document
      await _users.doc(u.uid).set({'photoURL': url}, SetOptions(merge: true));

      // 5. Update the FirebaseAuth profile as well
      await u.updatePhotoURL(url);
    } catch (e) {
      // Handle errors (e.g., log them)
      rethrow; // Rethrow to let the UI handle it
    }
  }

  Future<void> logout() async {
    // Remove this device's FCM token (and cancel the token-refresh listener)
    // before signing out, so notifications don't target a signed-out device
    // and a token can't bleed into the next account on this device.
    await NotificationService.instance.clearToken();
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

    // Linking is the irreversible step: once it succeeds the anonymous account
    // IS now an email account. If a later step (profile doc / verification
    // email) fails, we must NOT report a generic "registration failed" — that
    // would push the user to re-register an email that's already linked. Signal
    // a distinct 'partial-upgrade' so the UI can tell them to just log in.
    await user.linkWithCredential(cred);

    try {
      await user.updateDisplayName(name.trim());
      await user.getIdToken(true);
      await _ensureUserDoc(user, name: name.trim(), email: email.trim());
      await user.sendEmailVerification();
    } catch (e) {
      throw FirebaseAuthException(
        code: 'partial-upgrade',
        message:
            'Your account was created but we could not finish setting it up. '
            'Please log in and resend the verification email.',
      );
    }
  }

  // --- GOOGLE SIGN IN LOGIC ---
  /// Returns the signed-in [User], or `null` ONLY when the user cancelled the
  /// Google account picker. Any genuine failure (network, credential conflict,
  /// Firestore write) is rethrown so the caller can show the real error rather
  /// than a misleading "canceled" message.
  Future<User?> signInWithGoogle() async {
    // Trigger the Google authentication flow.
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      return null; // user cancelled the picker
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;

    // Create the Firestore profile on first sign-in (consistent schema).
    if (user != null) {
      await _ensureUserDoc(
        user,
        name: user.displayName ?? 'Google User',
        email: user.email ?? '',
        photoURL: user.photoURL,
      );
    }

    return user;
  }

  Future<void> saveUserToken() async {
    final user = currentUser;
    if (user == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _users.doc(user.uid).set({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Failed to save FCM token: $e');
    }
  }
}
