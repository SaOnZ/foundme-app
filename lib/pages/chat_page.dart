import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/claim_service.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../models/claim.dart';
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

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
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
        final status = (data['status'] ?? 'pending') as String;
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
            actions: [
              if (!isOwner) const SizedBox.shrink(),
              if (status == 'pending') ...[
                IconButton(
                  tooltip: 'Reject',
                  icon: const Icon(Icons.cancel_outlined),
                  onPressed: () async {
                    await ClaimService.instance.setClaimStatus(
                      widget.claimId,
                      'rejected',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Rejected')));
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Accept',
                  icon: const Icon(
                    Icons.check_circle_outline,
                  ), // <-- FIX 1: 'icon'
                  onPressed: () async {
                    await ClaimService.instance.setClaimStatus(
                      widget.claimId,
                      'accepted',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Accepted')));
                    }
                  },
                ),
              ],
              if (status == 'accepted')
                IconButton(
                  tooltip: 'Mark resolved',
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: () async {
                    try {
                      await ClaimService.instance.closeClaimAndItem(
                        // <-- FIX 2: 'closeClaimAndItem'
                        widget.claimId,
                        data['itemId'],
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        // <-- FIX 3: 'showSnackBar'
                        const SnackBar(content: Text('Closed ✔')),
                      );

                      final claimerUid =
                          data['claimerUid']; // <-- FIX 4: Missing '
                      final claimerProfile = await AuthService.instance
                          .getUserProfile(claimerUid);
                      final claimerName = // <-- FIX 5: 'claimerName'
                          claimerProfile?.name ?? 'the Claimer';

                      if (!context.mounted) return;

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => RatingDialog(
                          claimId: widget.claimId,
                          roleToReview: 'claimer',
                          personToReviewName:
                              claimerName, // <-- FIX 5: 'claimerName'
                        ),
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
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
                    return ListView.builder(
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

              // Input
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _c,
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () async {
                          final t = _c.text.trim();
                          if (t.isEmpty) return;
                          await ClaimService.instance.sendMessage(
                            widget.claimId,
                            t,
                          );
                          _c.clear();
                        },
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
