import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import '../models/claim.dart';
import '../models/status.dart';
import '../models/chat_message.dart';

/// Thrown when a claim action can't proceed (e.g. it was already accepted or
/// declined by someone else). Carries a user-facing [message].
class ClaimActionException implements Exception {
  final String message;
  ClaimActionException(this.message);
  @override
  String toString() => message;
}

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
        .where('status', whereIn: [ClaimStatus.pending, ClaimStatus.accepted])
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
      'status': ClaimStatus.pending,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Accept a claim. Runs in a transaction so a rapid double-tap or a second
  /// owner session can't accept twice, and uses the item doc as a lock
  /// (`acceptedClaimId`) so two *different* pending claims on the same item
  /// can't both be accepted. Other still-pending claims on the item are then
  /// declined (best-effort).
  Future<void> acceptClaim({
    required String claimId,
    required String itemId,
  }) async {
    if (itemId.isEmpty) {
      throw ClaimActionException('This claim is missing its item reference.');
    }
    await _db.runTransaction((txn) async {
      final claimRef = _claims.doc(claimId);
      final itemRef = _db.collection('items').doc(itemId);

      final claimSnap = await txn.get(claimRef);
      if (!claimSnap.exists) {
        throw ClaimActionException('This claim no longer exists.');
      }
      final claimData = claimSnap.data() as Map<String, dynamic>;
      final status = claimData['status'];
      if (status == ClaimStatus.accepted) return; // idempotent
      if (status != ClaimStatus.pending) {
        throw ClaimActionException('This claim can no longer be accepted.');
      }

      final itemSnap = await txn.get(itemRef);
      final existingAccepted =
          itemSnap.data()?['acceptedClaimId'];
      if (existingAccepted != null && existingAccepted != claimId) {
        throw ClaimActionException(
          'Another claim has already been accepted for this item.',
        );
      }

      txn.update(claimRef, {'status': 'accepted'});
      txn.update(itemRef, {'acceptedClaimId': claimId});
    });

    // Best-effort: decline the remaining pending claims on this item so the
    // owner isn't presented with claims that can no longer be accepted.
    try {
      final siblings = await _claims
          .where('itemId', isEqualTo: itemId)
          .where('status', isEqualTo: ClaimStatus.pending)
          .get();
      if (siblings.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final d in siblings.docs) {
          if (d.id == claimId) continue;
          batch.update(d.reference, {'status': ClaimStatus.declined});
        }
        await batch.commit();
      }
    } catch (_) {
      // Cleanup is non-critical; the item lock already guarantees correctness.
    }
  }

  /// Decline a claim transactionally. Safe against double-tap and clears the
  /// item lock if the claim being declined was the accepted one.
  Future<void> declineClaim({
    required String claimId,
    required String itemId,
  }) async {
    await _db.runTransaction((txn) async {
      final claimRef = _claims.doc(claimId);
      final claimSnap = await txn.get(claimRef);
      if (!claimSnap.exists) {
        throw ClaimActionException('This claim no longer exists.');
      }
      final claimData = claimSnap.data() as Map<String, dynamic>;
      final status = claimData['status'];
      if (status == ClaimStatus.declined) return; // idempotent
      if (status != ClaimStatus.pending && status != ClaimStatus.accepted) {
        throw ClaimActionException('This claim can no longer be declined.');
      }

      txn.update(claimRef, {'status': ClaimStatus.declined});

      // If this was the accepted claim, release the item lock.
      if (status == ClaimStatus.accepted && itemId.isNotEmpty) {
        final itemRef = _db.collection('items').doc(itemId);
        final itemSnap = await txn.get(itemRef);
        final accepted =
            itemSnap.data()?['acceptedClaimId'];
        if (accepted == claimId) {
          txn.update(itemRef, {'acceptedClaimId': FieldValue.delete()});
        }
      }
    });
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

  /// Streams the most recent [limit] messages for a claim. Fetches newest-first
  /// (so the limit keeps the latest messages) then returns them oldest-first
  /// for display. Bounding the query avoids loading an unbounded conversation.
  Stream<List<ChatMessage>> messages(String claimId, {int limit = 50}) {
    return _messages
        .where('claimId', isEqualTo: claimId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
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
    batch.update(db.collection('claims').doc(claimId), {
      'status': ClaimStatus.closed,
    });
    batch.update(db.collection('items').doc(itemId), {
      'status': ItemStatus.closed,
    });
    await batch.commit();
  }

  Stream<QuerySnapshot> streamUserClaimForItem(String itemId, String userId) {
    return FirebaseFirestore.instance
        .collection('claims')
        .where('itemId', isEqualTo: itemId)
        .where('claimerUid', isEqualTo: userId)
        .limit(1)
        .snapshots();
  }
}
