import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final Timestamp createdAt;
  final String? photoURL;

  final double averageRating;
  final int ratingCount;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.createdAt,
    this.photoURL,

    required this.averageRating,
    required this.ratingCount,
  });

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Helper to safely parse numbers
    double _asDouble(dynamic v) => (v is num) ? v.toDouble() : 0.0;
    int _asInt(dynamic v) => (v is num) ? v.toInt() : 0;

    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? 'user',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      photoURL: data['photoURL'],

      averageRating: _asDouble(data['averageRating']),
      ratingCount: _asInt(data['ratingCount']),
    );
  }
}
