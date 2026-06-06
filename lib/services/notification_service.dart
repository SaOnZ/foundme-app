import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'navigation_service.dart';
import '../pages/chat_page.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  final _foregroundMessageController =
      StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get foregroundMessages =>
      _foregroundMessageController.stream;

  // Listener subscriptions, retained so they can be cancelled and so init()
  // can be made idempotent (it used to be called from both main() and
  // HomePage.initState, double-registering every handler).
  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;

  Future<void> init() async {
    // Idempotent: only wire everything up once per app session.
    if (_initialized) return;
    _initialized = true;

    // 1. Request permission and respect the result. On iOS / Android 13+ a
    //    user can deny; don't fetch a token or register listeners in that case.
    final settings = await _messaging.requestPermission();
    final status = settings.authorizationStatus;
    if (status != AuthorizationStatus.authorized &&
        status != AuthorizationStatus.provisional) {
      return;
    }

    // 2. Get the token and save it to Firestore
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToFirestore(token);
    }

    // 3. Listen for token changes and save the new one
    _tokenRefreshSub = _messaging.onTokenRefresh.listen(_saveTokenToFirestore);

    // 4. Listen for messages when the app is in foreground
    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _foregroundMessageController.add(message);
      }
    });

    // 5. Handle taps
    _setupInteractedMessage();
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Add the new token to the array and drop the legacy singular field
      // in the same write, so older docs migrate themselves on the next save.
      await _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmToken': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  /// Removes this device's token from the signed-in user's doc and deletes it
  /// locally. Call this on logout (before sign-out) so notifications stop
  /// targeting a signed-out device and a token can't bleed across accounts.
  Future<void> clearToken() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    try {
      final uid = AuthService.instance.currentUser?.uid;
      final token = await _messaging.getToken();
      if (uid != null && token != null) {
        await _db.collection('users').doc(uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('Failed to clear FCM token: $e');
    }
  }

  /// Handles any interaction with a notification (tap)
  /// when the app is in the background or terminated.
  void _setupInteractedMessage() {
    // 1. Handles taps when the app is TERMINATED — the message that launched it.
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        _handleMessage(message);
      }
    });

    // 2. Handles taps when the app is in the BACKGROUND.
    _onOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  /// Navigates to the correct page based on the notification data.
  void _handleMessage(RemoteMessage message) {
    try {
      // data is Map<String, dynamic>; coerce defensively (a non-string
      // claimId would otherwise throw inside this fire-and-forget handler).
      final claimId = message.data['claimId']?.toString();
      if (claimId == null || claimId.isEmpty) return;

      // Only navigate a real, signed-in user into a chat. A tap received at
      // the login screen (or before auth restores) must not push ChatPage.
      final user = AuthService.instance.currentUser;
      if (user == null || user.isAnonymous) return;

      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => ChatPage(claimId: claimId)),
      );
    } catch (e) {
      debugPrint('Failed to handle notification tap: $e');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
    _onOpenedSub?.cancel();
    _foregroundMessageController.close();
  }
}
