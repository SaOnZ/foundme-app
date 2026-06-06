import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AiMatchingService {
  static final AiMatchingService instance = AiMatchingService._init();
  AiMatchingService._init();

  /// Asks the findMatchingItems Cloud Function to compare [itemId] against
  /// candidate items and return the ones Gemini considers a match.
  Future<List<Map<String, dynamic>>> findMatches({
    required String itemId,
    required Uint8List imageBytes,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('findMatchingItems')
          .call({
            'itemId': itemId,
            if (imageBytes.isNotEmpty) 'imageBase64': base64Encode(imageBytes),
          });

      final data = result.data;
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (e) {
      debugPrint('AI match lookup failed: $e');
      return [];
    }
  }
}
