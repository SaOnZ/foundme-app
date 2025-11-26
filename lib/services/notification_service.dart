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

  Future<void> init() async {
    // 1. Request permission from the user
    await _messaging.requestPermission();

    // 2. Get the token and save it to Firestore
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToFirestore(token);
    }

    // 3. Listen for token changes and save the new one
    _messaging.onTokenRefresh.listen(_saveTokenToFirestore);

    // 4. Listen for messages when the app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        // Show a SnackBar or a local notification
        _foregroundMessageController.add(message);
      }
    });

    // 5. Handle taps
    _setupInteractedMessage();
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return; //Not logged in

    try {
      await _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
    } catch (e) {
      // Handle error
    }
  }

  /// Handles any interaction with a notification (tap)
  /// when the app is in the background or terminated.
  void _setupInteractedMessage() {
    // 1. Handles Taps when Ap is TERMINATED
    // This gets the message that launched the app
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        _handleMessage(message);
      }
    });

    // 2. Handles Taps when App is in BACKGROUND
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  /// Navigates to the correct page based on the notification data
  void _handleMessage(RemoteMessage message) {
    //Get the claimId from the data payload
    final String? claimId = message.data['claimId'];

    if (claimId != null) {
      //Use the global key to navigate, no context needed!
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => ChatPage(claimId: claimId)),
      );
    }
  }

  void dispose() {
    _foregroundMessageController.close();
  }
}
