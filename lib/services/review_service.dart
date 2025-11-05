import 'package:cloud_functions/cloud_functions.dart';

class ReviewService {
  ReviewService._();
  static final instance = ReviewService._();

  final _functions = FirebaseFunctions.instance;

  /// Calls a Cloud Function to securely submit a review.
  Future<void> submitReview({
    required String claimId,
    required String roleToReview, // 'owner' or 'claimer'
    required double rating,
    String? comment, // Optional comment
  }) async {
    try {
      // we will create this cloud functions in the next part
      final callable = _functions.httpsCallable('submitReview');

      // send the data to the function
      await callable.call(<String, dynamic>{
        'claimId': claimId,
        'roleToReview': roleToReview,
        'rating': rating,
        'comment': comment,
      });
    } on FirebaseFunctionsException catch (e) {
      // re-throw a user-friendly message
      throw e.message ?? 'Failed to submit review. Please try again.';
    } catch (e) {
      throw 'An unknown error occurred.';
    }
  }
}
