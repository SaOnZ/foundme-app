/// Canonical status vocabularies shared across models, services, and UI.
///
/// Before this existed, claim/item statuses were spelled inconsistently
/// (e.g. `declined` vs `rejected`, `approved` vs `active`) which left dead
/// UI branches and mismatched chips. Use these constants everywhere instead
/// of bare string literals so the vocabulary stays in one place.

/// Lifecycle of a claim (a claimer's request against an item).
class ClaimStatus {
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const closed = 'closed';

  /// Legacy docs / admin tooling occasionally wrote `rejected` for a declined
  /// claim. Normalize so UI only ever has to handle the canonical value.
  static String normalize(String? raw) {
    if (raw == 'rejected') return declined;
    return raw ?? pending;
  }

  static bool isDeclined(String? raw) => normalize(raw) == declined;
}

/// Lifecycle of an item (a lost/found post).
class ItemStatus {
  static const pendingApproval = 'pending_approval';
  static const active = 'active';
  static const closed = 'closed';
  static const expired = 'expired';
  static const rejected = 'rejected';

  /// Legacy docs sometimes used `pending`/`approved`; map them onto the
  /// canonical values so admin views don't show dead/blank states.
  static String normalize(String? raw) {
    switch (raw) {
      case 'pending':
        return pendingApproval;
      case 'approved':
        return active;
      default:
        return raw ?? pendingApproval;
    }
  }
}
