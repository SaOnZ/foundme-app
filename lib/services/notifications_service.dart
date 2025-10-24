import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  Future<void> init(BuildContext context) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.notification!.title ?? 'New Message'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
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

  // TODO in Part 3: Add handlers for when user taps a notification
  // - FirebaseMessaging.onMessageOpenedApp.listen(...)
  // - _messaging.getInitialMessage().then(...)
}
