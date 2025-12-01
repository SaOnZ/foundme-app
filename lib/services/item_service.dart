import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'auth_service.dart';
import '../models/item.dart';
import 'package:mime/mime.dart';

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
      'status': 'active',
      'postedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<List<ItemModel>> latestActive() {
    return _items
        .where('status', isEqualTo: 'active')
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
    return _items
        .where('status', isEqualTo: 'active')
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
}
