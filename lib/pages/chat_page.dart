import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/claim_service.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../models/status.dart';
import '../widgets/rating_dialog.dart';
import '../models/user_model.dart';

class ChatPage extends StatefulWidget {
  final String claimId;
  const ChatPage({super.key, required this.claimId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  bool _actionBusy = false;
  bool _sending = false;

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _sendMessage() async {
    final t = _c.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ClaimService.instance.sendMessage(widget.claimId, t);
      if (!mounted) return;
      _c.clear(); // only clear once the send actually succeeded
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message failed to send. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Opens the rating dialog for the other party. [role] is 'claimer' (owner
  /// rates the claimer) or 'owner' (claimer rates the owner).
  Future<void> _rate(String role, String otherUid) async {
    final profile = otherUid.isEmpty
        ? null
        : await AuthService.instance.getUserProfileCached(otherUid);
    if (!mounted) return;
    final name =
        profile?.name ?? (role == 'claimer' ? 'the Claimer' : 'the Owner');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => RatingDialog(
        claimId: widget.claimId,
        roleToReview: role,
        personToReviewName: name,
      ),
    );
  }

  /// Owner marks the claim resolved (closes claim + item), then is prompted to
  /// rate the claimer — but only if they haven't already reviewed.
  Future<void> _resolve(Map<String, dynamic> data) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await ClaimService.instance.closeClaimAndItem(
        widget.claimId,
        (data['itemId'] ?? '') as String,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Closed ✔')));
      final ownerReviewed = (data['ownerHasReviewed'] ?? false) as bool;
      if (!ownerReviewed) {
        await _rate('claimer', (data['claimerUid'] ?? '') as String);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not resolve. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// Runs an owner claim action (accept/decline) guarding against double-tap
  /// and surfacing a user-facing message on success/failure.
  Future<void> _runClaimAction(
    Future<void> Function() action,
    String successMsg,
  ) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMsg)));
    } on ClaimActionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Widget _buildSafetyNudge(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Safety Tip: Never pay or give personal info to get an item back. Always meet in a safe, public place.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService.instance.currentUser!.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('claims')
          .doc(widget.claimId)
          .snapshots(),
      builder: (context, snap) {
        // Build a basic scaffold while loading
        if (!snap.hasData || !snap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading Chat...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // all logic is now inside the builder
        final data = snap.data!.data() as Map<String, dynamic>;
        final isOwner = data['ownerUid'] == me;
        final status = ClaimStatus.normalize(data['status'] as String?);
        final otherUserUid = isOwner ? data['claimerUid'] : data['ownerUid'];

        return Scaffold(
          appBar: AppBar(
            // --- DYNAMIC TITLE ---
            title: StreamBuilder<UserModel?>(
              stream: AuthService.instance.userStream(uid: otherUserUid),
              builder: (context, userSnap) {
                if (!userSnap.hasData) {
                  return const Text('Loading...');
                }
                final otherUser = userSnap.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(otherUser.name, style: const TextStyle(fontSize: 18)),
                    if (otherUser.ratingCount > 0)
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${otherUser.averageRating.toStringAsFixed(1)} (${otherUser.ratingCount})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      )
                    else
                      const Text(
                        'No reviews yet',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                );
              },
            ),
            // --- ACTIONS ---
            // Claim state transitions (accept/decline/resolve) are owner-only
            // per firestore.rules: the claimer can only push status to
            // 'closed', and rating the owner happens from MyClaimsPage once
            // the claim is closed. Showing these buttons to the claimer used
            // to silently fail at the rules layer.
            actions: [
              if (isOwner && status == ClaimStatus.pending) ...[
                IconButton(
                  tooltip: 'Decline',
                  icon: const Icon(Icons.cancel_outlined),
                  onPressed: _actionBusy
                      ? null
                      : () => _runClaimAction(
                          () => ClaimService.instance.declineClaim(
                            claimId: widget.claimId,
                            itemId: (data['itemId'] ?? '') as String,
                          ),
                          'Declined',
                        ),
                ),
                IconButton(
                  tooltip: 'Accept',
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: _actionBusy
                      ? null
                      : () => _runClaimAction(
                          () => ClaimService.instance.acceptClaim(
                            claimId: widget.claimId,
                            itemId: (data['itemId'] ?? '') as String,
                          ),
                          'Accepted',
                        ),
                ),
              ],
              if (isOwner && status == ClaimStatus.accepted)
                IconButton(
                  tooltip: 'Mark resolved',
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: _actionBusy ? null : () => _resolve(data),
                ),
              // Persistent rating entry once the claim is closed, so a
              // dismissed rating dialog can still be completed later.
              if (status == ClaimStatus.closed &&
                  isOwner &&
                  !((data['ownerHasReviewed'] ?? false) as bool))
                TextButton(
                  onPressed: () =>
                      _rate('claimer', (data['claimerUid'] ?? '') as String),
                  child: const Text('Rate claimer'),
                ),
              if (status == ClaimStatus.closed &&
                  !isOwner &&
                  !((data['claimerHasReviewed'] ?? false) as bool))
                TextButton(
                  onPressed: () =>
                      _rate('owner', (data['ownerUid'] ?? '') as String),
                  child: const Text('Rate owner'),
                ),
            ],
          ),

          body: Column(
            children: [
              // Claim header (status)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text('Status: $status'),
              ),

              _buildSafetyNudge(context),

              // Messages
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: ClaimService.instance.messages(widget.claimId),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final msgs = snap.data!;
                    if (msgs.isEmpty) {
                      return const Center(child: Text('No messages yet.'));
                    }
                    // Jump to the newest message after this frame renders.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToBottom(),
                    );
                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) {
                        final m = msgs[i];
                        final mine = m.senderUid == me;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(m.text),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              if (status == ClaimStatus.declined ||
                  status == ClaimStatus.closed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: Colors.grey[200],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'This conversation is closed.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Input
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _c,
                            maxLength: ClaimService.maxMessageLength,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: 'Type a message',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _sending ? null : _sendMessage,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
