import 'package:cloud_firestore/cloud_firestore.dart';

class ClaimModel {
  final String id;
  final String itemId;
  final String ownerUid;
  final String claimerUid;
  final String message; // initial message
  final String status; // pending | accepted | rejected | closed
  final Timestamp createdAt;

  ClaimModel({
    required this.id,
    required this.itemId,
    required this.ownerUid,
    required this.claimerUid,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  factory ClaimModel.fromDoc(DocumentSnapshot d) {
    final m = (d.data() ?? {}) as Map<String, dynamic>;
    return ClaimModel(
      id: d.id,
      itemId: m['itemId'] ?? '',
      ownerUid: m['ownerUid'] ?? '',
      claimerUid: m['claimerUid'] ?? '',
      message: m['message'] ?? '',
      status: m['status'] ?? 'pending',
      createdAt: (m['createdAt'] is Timestamp)
          ? m['createdAt']
          : Timestamp.now(),
    );
  }
}
