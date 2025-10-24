import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import '../models/claim.dart';
import '../models/chat_message.dart';

class ClaimService {
  ClaimService._();
  static final instance = ClaimService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference get _claims => _db.collection('claims');
  CollectionReference get _messages => _db.collection('messages');

  /// Create a claim; prevents duplicate active claims by the same claimer on the same item.
  Future<String> createClaim({
    required String itemId,
    required String ownerUid,
    required String initialMessage,
  }) async {
    final uid = AuthService.instance.currentUser!.uid;
    // block duplicate pending/accepted claims by same user on same item
    final dup = await _claims
        .where('itemId', isEqualTo: itemId)
        .where('claimerUid', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) {
      return dup.docs.first.id;
    }

    final doc = _claims.doc();
    await doc.set({
      'itemId': itemId,
      'ownerUid': ownerUid,
      'claimerUid': uid,
      'message': initialMessage.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> setClaimStatus(String claimId, String status) async {
    // status in: pending | accepted | rejected | closed
    await _claims.doc(claimId).update({'status': status});
  }

  // Streams
  Stream<List<ClaimModel>> incomingForOwner(String ownerUid) {
    return _claims
        .where('ownerUid', isEqualTo: ownerUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ClaimModel.fromDoc).toList());
  }

  Stream<List<ClaimModel>> myClaims(String claimerUid) {
    return _claims
        .where('claimerUid', isEqualTo: claimerUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ClaimModel.fromDoc).toList());
  }

  // Chat
  Future<void> sendMessage(String claimId, String text) async {
    final uid = AuthService.instance.currentUser!.uid;
    await _messages.add({
      'claimId': claimId,
      'senderUid': uid,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<ChatMessage>> messages(String claimId) {
    return _messages
        .where('claimId', isEqualTo: claimId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) {
          final list = s.docs.map(ChatMessage.fromDoc).toList();
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return list;
        });
  }

  Future<void> closeClaimAndItem(String claimId, String itemId) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(db.collection('claims').doc(claimId), {'status': 'closed'});
    batch.update(db.collection('items').doc(itemId), {'status': 'closed'});
    await batch.commit();
  }
}
