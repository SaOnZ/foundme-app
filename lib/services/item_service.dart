import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'auth_service.dart';
import '../models/item.dart';
import 'package:mime/mime.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/log_service.dart';

class ItemService {
  ItemService._();
  static final instance = ItemService._();

  final _items = FirebaseFirestore.instance.collection('items');
  final _storage = FirebaseStorage.instance;

  Stream<List<ItemModel>> myItems(String ownerUid) {
    return _items
        .where('ownerUid', isEqualTo: ownerUid)
        .orderBy('postedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ItemModel.fromDoc).toList());
  }

  Future<void> updateItem(String id, Map<String, dynamic> fields) async {
    await _items.doc(id).update(fields);
  }

  Future<void> closeItem(String id) async {
    await updateItem(id, {'status': 'closed'});
  }

  Future<void> reopenItem(String id) async {
    await updateItem(id, {'status': 'active'});
  }

  Future<void> deleteItem(ItemModel it) async {
    await _items.doc(it.id).delete();
    for (final url in it.photos) {
      try {
        await _storage.refFromURL(url).delete();
      } catch (_) {
        // ignore errors
      }
    }
  }

  Future<List<String>> _uploadPhotos(String itemId, List<XFile> files) async {
    final uid = AuthService.instance.currentUser!.uid;
    final urls = <String>[];

    for (final f in files) {
      final file = File(f.path);

      final bytes = await file.length();
      if (bytes > 10 * 1024 * 1024) {
        throw 'Image ${f.name} is too large (max 10MB) ';
      }

      final contentType = lookupMimeType(f.path) ?? 'image/jpeg';
      final name = '${DateTime.now().millisecondsSinceEpoch}_${Uuid().v4()}';
      final ref = _storage.ref('items/$uid/$itemId/$name');

      final task = await ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      urls.add(await task.ref.getDownloadURL());
    }
    return urls;
  }

  Future<String> createItem({
    required String type,
    required String title,
    required String desc,
    required String category,
    required List<String> tags,
    required double lat,
    required double lng,
    required String locationText,
    required List<XFile> photos,
  }) async {
    final uid = AuthService.instance.currentUser!.uid;
    final doc = _items.doc();
    final urls = await _uploadPhotos(doc.id, photos);
    await doc.set({
      'ownerUid': uid,
      'type': type,
      'title': title.trim(),
      'desc': desc.trim(),
      'category': category,
      'tags': tags,
      'lat': lat,
      'lng': lng,
      'locationText': locationText,
      'photos': urls,
      'status': 'pending_approval',
      'postedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  //Define the time limit
  final Duration _expiryDuration = const Duration(days: 90);

  Stream<List<ItemModel>> latestActive() {
    // Calculate the cutoff data (90 days ago)
    final DateTime cutoff = DateTime.now().subtract(_expiryDuration);
    final Timestamp cutoffTs = Timestamp.fromDate(cutoff);

    return _items
        .where('status', isEqualTo: 'active')
        .where('postedAt', isGreaterThan: cutoffTs) // only get newer items
        .orderBy('postedAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) {
                try {
                  return ItemModel.fromDoc(d);
                } catch (_) {
                  return null;
                }
              })
              .whereType<ItemModel>()
              .toList(),
        );
  }

  Stream<List<ItemModel>> allActiveItems() {
    final DateTime cutoff = DateTime.now().subtract(_expiryDuration);
    final Timestamp cutoffTs = Timestamp.fromDate(cutoff);
    return _items
        .where('status', isEqualTo: 'active')
        .where('postedAt', isGreaterThan: cutoffTs)
        .orderBy('postedAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) {
                try {
                  return ItemModel.fromDoc(d);
                } catch (_) {
                  return null;
                }
              })
              .whereType<ItemModel>()
              .toList(),
        );
  }

  /// Getx a stream for a single item from its ID.
  Stream<ItemModel> getItemStream(String id) {
    return _items.doc(id).snapshots().map(ItemModel.fromDoc);
  }

  Stream<List<ItemModel>> adminGetAllItems() {
    return _items
        .orderBy('postedAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) {
                try {
                  return ItemModel.fromDoc(d);
                } catch (_) {
                  return null;
                }
              })
              .whereType<ItemModel>()
              .toList(),
        );
  }

  Future<List<ItemModel>> getMatchingCandidates({
    required String currentType,
    required String category,
  }) async {
    try {
      // If i lost something, I am looking for 'found' items and vice versa
      final targetType = currentType == 'lost' ? 'found' : 'lost';

      final snapshot = await FirebaseFirestore
          .instance // or FirebaseFirestore.instance
          .collection('items')
          .where('type', isEqualTo: targetType)
          .where('category', isEqualTo: category)
          .where('status', isEqualTo: 'active') // Only match active items
          .orderBy('postedAt', descending: true) // Newest first
          .limit(20) // Limit to 20 to save AI tokens
          .get();

      return snapshot.docs.map((doc) {
        return ItemModel.fromDoc(doc);
      }).toList();
    } catch (e) {
      print('Error fetching matches: $e');
      return [];
    }
  }

  // Call this occasionally to clean up old data
  Future<int> autoExpireOldItems() async {
    final DateTime cutoff = DateTime.now().subtract(_expiryDuration);
    final Timestamp cutoffTs = Timestamp.fromDate(cutoff);

    // Find active items older than cutoff
    final snapshot = await _items
        .where('status', isEqualTo: 'active')
        .where('postedAt', isLessThan: cutoffTs)
        .get();

    // Update them in a batch
    final batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'status': 'expired'});
      count++;

      final data = doc.data() as Map<String, dynamic>;
      final title = data['title'] ?? 'Unknown Item';

      LogService.instance.logActivity(
        "Item Expired",
        "Item '${doc['title']}' auto-expired (90+ days)",
        "expired",
      );
    }

    if (count > 0) {
      await batch.commit();
      print("🧹 Auto-expired $count old items.");
    }

    return count;
  }

  Stream<List<ItemModel>> getPendingApprovalItems() {
    return _items
        .where('status', isEqualTo: 'pending_approval')
        .orderBy('postedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ItemModel.fromDoc).toList());
  }

  Future<void> setItemStatus(String itemId, String newStatus) async {
    //Update Database
    await _items.doc(itemId).update({'status': newStatus});

    try {
      // Fetch Item to get Owner ID and Title
      final itemDoc = await _items.doc(itemId).get();
      if (!itemDoc.exists) return;

      final ownerUid = itemDoc.data()?['ownerUid'];
      final title = itemDoc.data()?['title'] ?? 'Item';

      if (ownerUid != null) {
        // Prepare Message based on Status
        String titleMsg = newStatus == 'active'
            ? 'Post Approved! ✅'
            : 'Post Rejected ❌';
        String bodyMsg = newStatus == 'active'
            ? 'Your item "$title" is now visible in the feed.'
            : 'Your post "$title" was not approved.';

        // Send the notification
        await _sendAdminNotification(ownerUid, titleMsg, bodyMsg);
      }
    } catch (e) {
      print("Error sending admin notification: $e");
    }
  }

  Future<void> _sendAdminNotification(
    String targetUid,
    String title,
    String body,
  ) async {
    try {
      // Get Token from Users Collection
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .get();
      String? token;

      if (userDoc.exists) {
        final data = userDoc.data()!;
        if (data['fcmToken'] is String) {
          token = data['fcmToken'];
        } else if (data['fcmTokens'] is List &&
            (data['fcmTokens'] as List).isNotEmpty) {
          token = (data['fcmTokens'] as List).last.toString();
        }
      }

      if (token == null) return;

      // Authenticate with Service Account
      final serviceAccountJson = {
        "type": "service_account",
        "project_id": dotenv.env['FCM_PROJECT_ID'],
        "private_key_id": "5bee0dd0b3bb2351ba79014732bf2ebeb9712a54",
        "private_key":
            dotenv.env['FCM_PRIVATE_KEY']?.replaceAll('\\n', '\n') ?? "",
        "client_email": dotenv.env['FCM_CLIENT_EMAIL'],
        "client_id": "108810556853786570043",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url":
            "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url":
            "https://www.googleapis.com/robot/v1/metadata/x509/${dotenv.env['FCM_CLIENT_EMAIL']}",
        "universe_domain": "googleapis.com",
      };

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final credentials = auth.ServiceAccountCredentials.fromJson(
        serviceAccountJson,
      );
      final client = await auth.clientViaServiceAccount(credentials, scopes);

      // Send Request to FCM V1
      await client.post(
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/foundme-28322/messages:send',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "android": {
              "priority": "high",
              "notification": {"channel_id": "high_importance_channel"},
            },
          },
        }),
      );
      client.close();
      print("Admin notification sent to user.");
    } catch (e) {
      print("Failed to send admin notification: $e");
    }
  }
}
