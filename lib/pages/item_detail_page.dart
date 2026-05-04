import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/claim_service.dart';
import 'chat_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/report_dialog.dart';
import 'profile_page.dart';
import '../models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/rate_user_sheet.dart';

class ItemDetailPage extends StatelessWidget {
  final ItemModel item;
  const ItemDetailPage({super.key, required this.item});

  // 1. Function to Delete Item
  Future<void> _deleteItem(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('items')
          .doc(item.id)
          .delete();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Post deleted.')));
        Navigator.pop(context); // Go back to Home
      }
    }
  }

  // 2. Function to Mark as Resolved
  Future<void> _markResolved(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Resolved?'),
        content: const Text(
          'This means you found the item. The post will be closed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Look up the accepted claim so we can close the claim alongside the
    // item and pass the real claim id (not the item id) to the rating
    // sheet — submitReview reads claims/{claimId}, so the previous
    // implementation always failed with not-found.
    final acceptedClaim = await FirebaseFirestore.instance
        .collection('claims')
        .where('itemId', isEqualTo: item.id)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();

    if (acceptedClaim.docs.isEmpty) {
      // No accepted claim (owner found the item without anyone claiming it).
      // Close the item; nobody to rate.
      await FirebaseFirestore.instance
          .collection('items')
          .doc(item.id)
          .update({'status': 'closed'});
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Item closed.')));
      }
      return;
    }

    final claimDoc = acceptedClaim.docs.first;
    final claimerUid = (claimDoc.data())['claimerUid'] as String?;
    await ClaimService.instance.closeClaimAndItem(claimDoc.id, item.id);

    final claimerName = claimerUid == null
        ? 'the Claimer'
        : (await AuthService.instance.getUserProfile(claimerUid))?.name ??
            'the Claimer';

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Item resolved. Please rate the claimer.'),
      ),
    );
    _showRatingSheet(context, claimDoc.id, claimerName);
  }

  void _showRatingSheet(
    BuildContext context,
    String claimId,
    String claimerName,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RateUserSheet(
        targetUserName: claimerName,
        claimId: claimId,
        roleToReview: "claimer",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final isGuest = AuthService.instance.isGuest;
    final uid = user?.uid;
    final isOwner = uid == item.ownerUid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item detail'),
        actions: [
          // Show report button if user is logged in AND not the owner
          if (!isOwner && !isGuest)
            IconButton(
              icon: const Icon(Icons.report_outlined),
              tooltip: 'Report Item',
              onPressed: () {
                // Show the dialog we created
                showDialog(
                  context: context,
                  builder: (ctx) => ReportDialog(
                    reportedItemId: item.id,
                    reportedUid: item.ownerUid,
                  ),
                );
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (item.photos.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: item.photos.first,
                height: 220,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 220,
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 220,
                  color: Colors.grey[200],
                  child: const Icon(Icons.error, color: Colors.red, size: 40),
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Title + basic info
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          //Text('${item.type.toUpperCase()} • ${item.category}'),
          Row(
            children: [
              Text(
                '${item.type.toUpperCase()} • ${item.category}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const Spacer(), //Pushes the data to the right edge
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                item.postedAt != null
                    ? _timeAgo(item.postedAt!.toDate())
                    : 'Unknown date',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(item.desc),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(item.locationText)),
            ],
          ),
          const SizedBox(height: 24),

          // Owner info
          const Divider(),
          FutureBuilder<UserModel?>(
            future: AuthService.instance.getUserProfile(item.ownerUid),
            builder: (context, snapshot) {
              // show a placholder while loading
              if (!snapshot.hasData || snapshot.hasError) {
                return const ListTile(
                  leading: CircleAvatar(child: Icon(Icons.person)),
                  title: Text('Posted by...'),
                  subtitle: Text('Loading user rating...'),
                );
              }

              final owner = snapshot.data!;

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: (owner.photoURL != null)
                      ? CachedNetworkImageProvider(owner.photoURL!)
                      : null,
                  child: (owner.photoURL == null)
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text('Posted by ${owner.name}'),
                subtitle: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${owner.averageRating.toStringAsFixed(1)} (${owner.ratingCount} ${owner.ratingCount == 1 ? "review" : "reviews"})',
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // Navigate to the owner's profile page
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfilePage(userId: owner.uid),
                    ),
                  );
                },
              );
            },
          ),
          const Divider(),
          const SizedBox(height: 24),

          // Action area
          if (isOwner)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.manage_accounts, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        "Owner Controls",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // DELETE BUTTON
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () => _deleteItem(context),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text("Delete"),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // RESOLVE BUTTON (Only show if not already closed)
                      if (item.status != 'closed')
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _markResolved(context),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text("Resolve"),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            )
          else if (item.status != 'active')
            const Center(
              child: Text(
                'This post is not active.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.red,
                ),
              ),
            )
          else if (isGuest)
            // Guest: prompt to register
            OutlinedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Register to claim'),
              onPressed: () => Navigator.pushNamed(context, '/register'),
            )
          else
            StreamBuilder<QuerySnapshot>(
              stream: ClaimService.instance.streamUserClaimForItem(
                item.id,
                uid!,
              ),
              builder: (context, snapshot) {
                // loading state
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 50,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                bool isPending = false;
                bool isDeclined = false;
                bool isAccepted = false;

                // Check Database Status
                if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                  final data =
                      snapshot.data!.docs.first.data() as Map<String, dynamic>;
                  final status = data['status'];

                  if (status == 'pending') isPending = true;
                  if (status == 'declined') isDeclined = true;
                  if (status == 'accepted') isAccepted = true;
                }

                // Logic: Show "Accepted" (Green)
                if (isAccepted) {
                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text(
                      'Claim Accepted!',
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: () {
                      // optionally navigate to chat history
                    },
                  );
                }

                // Logic: Show "Pending" (Grey/Disabled)
                if (isPending) {
                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                    ),
                    icon: const Icon(
                      Icons.hourglass_empty,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Request Sent',
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: null,
                  );
                }

                // Logic: Show "Declined" (Red Text + Retry Button)
                if (isDeclined) {
                  return Column(
                    children: [
                      const Text(
                        'Your previous request was declined.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                      const SizedBox(height: 5),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        onPressed: () => _handleClaim(context),
                      ),
                    ],
                  );
                }

                // Default: Show Normal Claim Button
                return ElevatedButton.icon(
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Claim this item'),
                  onPressed: () => _handleClaim(context),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _handleClaim(BuildContext context) async {
    final msg = await showDialog<String>(
      context: context,
      builder: (_) => const _InitialMessageDialog(),
    );
    if (msg == null || msg.trim().isEmpty) return;

    // Signed-in user (not owner) & active: can claim
    /*           ElevatedButton.icon(
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Claim this item'),
              onPressed: () async {
                // Ask for initial message
                final msg = await showDialog<String>(
                  context: context,
                  builder: (_) => const _InitialMessageDialog(),
                );
                if (msg == null || msg.trim().isEmpty) return; */

    try {
      final claimId = await ClaimService.instance.createClaim(
        itemId: item.id,
        ownerUid: item.ownerUid,
        initialMessage: msg.trim(),
      );

      if (!context.mounted) return;

      // The onNewClaimV2 Cloud Function trigger fires on the new claim doc
      // and sends the FCM notification to the owner; no client-side send.

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Claim request sent')));
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatPage(claimId: claimId)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send claim: $e')));
    }
  }
}

class _InitialMessageDialog extends StatefulWidget {
  const _InitialMessageDialog();

  @override
  State<_InitialMessageDialog> createState() => _InitialMessageDialogState();
}

class _InitialMessageDialogState extends State<_InitialMessageDialog> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Message to owner'),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Hi, I think this is mine...',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _c.text),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

// Helper: Convert Timestamp to "Time Ago" string
String _timeAgo(DateTime date) {
  final now = DateTime.now();
  final difference = now.difference(date);

  if (difference.inDays > 365) {
    return '${(difference.inDays / 365).floor()}y ago';
  } else if (difference.inDays > 30) {
    return '${(difference.inDays / 30).floor()}mo ago';
  } else if (difference.inDays > 0) {
    return '${difference.inDays}d ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}h ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}m ago';
  } else {
    return 'Just now';
  }
}
