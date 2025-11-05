import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/claim_service.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../models/claim.dart';
import '../widgets/rating_dialog.dart';

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

  @override
  Widget build(BuildContext context) {
    final me = AuthService.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Claim chat'),
        actions: [
          // Actions depend on who you are (owner?) and claim status
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('claims')
                .doc(widget.claimId)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData || !snap.data!.exists) {
                return const SizedBox.shrink();
              }
              final data = snap.data!.data() as Map<String, dynamic>;
              final isOwner = data['ownerUid'] == me;
              final status = (data['status'] ?? 'pending') as String;

              if (!isOwner) return const SizedBox.shrink();

              // While pending → Accept / Reject
              if (status == 'pending') {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Reject',
                      icon: const Icon(Icons.cancel_outlined),
                      onPressed: () async {
                        await ClaimService.instance.setClaimStatus(
                          widget.claimId,
                          'rejected',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Rejected')),
                          );
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Accept',
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: () async {
                        await ClaimService.instance.setClaimStatus(
                          widget.claimId,
                          'accepted',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Accepted')),
                          );
                        }
                      },
                    ),
                  ],
                );
              }

              // After accepted → Mark resolved (closes claim + item)
              if (status == 'accepted') {
                return IconButton(
                  tooltip: 'Mark resolved',
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: () async {
                    try {
                      // 1. Close the claim
                      await ClaimService.instance.closeClaimAndItem(
                        widget.claimId,
                        data['itemId'],
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Closed ✔')));

                      // 2. Get the claimer's ID
                      final claimerUid = data['claimerUid'];

                      // 3. Get their name using our new function
                      final claimerProfile = await AuthService.instance
                          .getUserProfile(claimerUid);
                      final claimerName = claimerProfile?.name ?? 'the Claimer';

                      if (!context.mounted) return;

                      // 4.  Show the rating dialog
                      showDialog(
                        context: context,
                        barrierDismissible: false, // Don't let them skip it
                        builder: (_) => RatingDialog(
                          claimId: widget.claimId,
                          roleToReview: 'claimer', // Owner rates the claimer
                          personToReviewName: claimerName,
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
                );
              }

              // rejected/closed → no actions
              return const SizedBox.shrink();
            },
          ),
        ],
      ),

      body: Column(
        children: [
          // Claim header (status)
          StreamBuilder<ClaimModel>(
            stream: FirebaseFirestore.instance
                .collection('claims')
                .doc(widget.claimId)
                .snapshots()
                .map((d) => ClaimModel.fromDoc(d)),
            builder: (context, snap) {
              final status = snap.hasData ? snap.data!.status : '...';
              return Container(
                width: double.infinity,
                // ignore: deprecated_member_use
                color: Theme.of(context).colorScheme.surfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text('Status: $status'),
              );
            },
          ),

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
                              ? Theme.of(context).colorScheme.primaryContainer
                              // ignore: deprecated_member_use
                              : Theme.of(context).colorScheme.surfaceVariant,
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
  }
}
