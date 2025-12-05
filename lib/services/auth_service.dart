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

  Stream<List<UserModel>> adminGetAllUsers() {
    return _users
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(UserModel.fromDoc).toList());
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

  Future<void> saveUserToken() async {
    print("🔥 DEBUG: Starting saveUserToken()...");

    try {
      // Get the current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("❌ DEBUG: User is NOT logged in. Cannot save token.");
        return;
      }

      // Try to get the token
      String? token = await FirebaseMessaging.instance.getToken();

      // Save it to Firestore
      if (token != null) {
        print("⚠️ DEBUG: Token was null. Waiting for Firebase to wake up...");
        await Future.delayed(const Duration(seconds: 3));
        token = await FirebaseMessaging.instance.getToken();
      }

      // If it is still null, give up
      if (token == null) {
        print("❌ DEBUG: Failed to get Token after retry. Check Internet.");
        return;
      }

      print("✅ DEBUG: Got Device Token: $token");

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'lastActive': DateTime.now(),
      }, SetOptions(merge: true));

      print("🚀 DEBUG: SUCCESS! Token written to Firestore.");
    } catch (e) {
      print("☠️ DEBUG: CRASH inside saveUserToken: $e");
    }
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

  // --- GOOGLE SIGN IN LOGIC ---
  Future<User?> signInWithGoogle() async {
    try {
      // Trigger the google Authentication flow
      final GoogleSignIn googleSignIn =
          GoogleSignIn(); // Ensure this is imported
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the credential
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      final User? user = userCredential.user;

      // Save User to Firestore (if new)
      if (user != null) {
        // Check if user doc exists
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!userDoc.exists) {
          // Create new user profile
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'uid': user.uid,
                'email': user.email,
                'name': user.displayName ?? 'Google User',
                'role': 'user',
                'createdAt': FieldValue.serverTimestamp(),
                'photoURL': user.photoURL,
                'ratingCount': 0,
                'averageRating': 0.0,
                'fcmTokens': [],
              });
        }
      }

      return user;
    } catch (e) {
      print("Error signing in with Google: $e");
      return null;
    }
  }
}
