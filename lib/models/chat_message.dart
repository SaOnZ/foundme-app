import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String claimId;
  final String senderUid;
  final String text;
  final Timestamp createdAt;

  ChatMessage({
    required this.id,
    required this.claimId,
    required this.senderUid,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot d) {
    final m = (d.data() ?? {}) as Map<String, dynamic>;
    return ChatMessage(
      id: d.id,
      claimId: m['claimId'] ?? '',
      senderUid: m['senderUid'] ?? '',
      text: m['text'] ?? '',
      createdAt: (m['createdAt'] is Timestamp)
          ? m['createdAt']
          : Timestamp.now(),
    );
  }
}
