import 'package:cloud_functions/cloud_functions.dart';

class ReviewService {
  ReviewService._();
  static final instance = ReviewService._();

  final _functions = FirebaseFunctions.instance;

  Future<void> submitReview({
    required String claimId,
    required String roleToReview, // 'owner' or 'claimer'
    required double rating,
    String? comment,
    List<String>? tags, // 🔥 NEW: Add tags parameter
  }) async {
    try {
      final callable = _functions.httpsCallable('submitReview');

      await callable.call(<String, dynamic>{
        'claimId': claimId,
        'roleToReview': roleToReview,
        'rating': rating,
        'comment': comment,
        'tags': tags ?? [],
      });
    } on FirebaseFunctionsException catch (e) {
      throw e.message ?? 'Failed to submit review. Please try again.';
    } catch (e) {
      throw 'An unknown error occurred.';
    }
  }
}
