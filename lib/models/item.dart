// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:cloud_firestore/cloud_firestore.dart';

class ItemModel {
  final String id;
  final String ownerUid;
  final String type;
  final String title;
  final String desc;
  final String category;
  final List<String> tags;
  final double lat;
  final double lng;
  final String locationText;
  final List<String> photos;
  final String status;
  final Timestamp postedAt;

  ItemModel({
    required this.id,
    required this.ownerUid,
    required this.type,
    required this.title,
    required this.desc,
    required this.category,
    required this.tags,
    required this.lat,
    required this.lng,
    required this.locationText,
    required this.photos,
    required this.status,
    required this.postedAt,
  });

  Map<String, dynamic> toMap() => {
    'ownerUid': ownerUid,
    'type': type,
    'title': title,
    'desc': desc,
    'category': category,
    'tags': tags,
    'lat': lat,
    'lng': lng,
    'locationText': locationText,
    'photos': photos,
    'status': status,
    'postedAt': postedAt,
  };

  factory ItemModel.fromDoc(DocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;

    // Helpers that won't crash on odd types
    String _asString(dynamic v) => v?.toString() ?? '';
    List<String> _asStringList(dynamic v) =>
        (v is List ? v.map((e) => e.toString()).toList() : <String>[]);

    Timestamp _asTimestamp(dynamic v) {
      if (v is Timestamp) return v;
      if (v is int) return Timestamp.fromMillisecondsSinceEpoch(v);
      if (v is String) {
        return Timestamp.now();
      }
      return Timestamp.now();
    }

    double _asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0.0;
    }

    return ItemModel(
      id: d.id,
      ownerUid: _asString(m['ownerUid']),
      type: _asString(m['type']),
      title: _asString(m['title']),
      desc: _asString(m['desc']),
      category: _asString(m['category']),
      tags: _asStringList(m['tags']),
      lat: _asDouble(m['lat']),
      lng: _asDouble(m['lng']),
      locationText: _asString(m['locationText']),
      photos: _asStringList(m['photos']),
      status: _asString(m['status']),
      postedAt: _asTimestamp(m['postedAt']),
    );
  }
}
