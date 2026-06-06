import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/claim_service.dart';
import '../models/claim.dart';
import 'chat_page.dart';
import '../models/item.dart';
import '../models/user_model.dart';
import '../services/item_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ClaimsInboxPage extends StatelessWidget {
  const ClaimsInboxPage({super.key});

  Widget _buildStatusChip(String status) {
    Color chipColor;
    String label;

    switch (status) {
      case 'accepted':
        chipColor = Colors.green;
        label = 'Accepted';
        break;
      case 'declined':
        chipColor = Colors.red;
        label = 'Declined';
        break;
      case 'closed':
        chipColor = Colors.grey;
        label = 'Closed';
        break;
      default: // pending
        chipColor = Colors.orange;
        label = 'Pending';
    }

    return Chip(
      label: Text(label, style: TextStyle(color: chipColor)),
      backgroundColor: chipColor.withOpacity(0.15),
      side: BorderSide(color: chipColor.withOpacity(0.3)),
      padding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Guest/signed-out users: block wih a friendly prompt
    if (AuthService.instance.isGuest ||
        AuthService.instance.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Claims inbox')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please sign in to view claims on your posts.'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: const Text('Go to login'),
              ),
            ],
          ),
        ),
      );
    }

    final owner = AuthService.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Claims inbox')),
      body: StreamBuilder<List<ClaimModel>>(
        stream: ClaimService.instance.incomingForOwner(owner),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final claims = snap.data!;
          if (claims.isEmpty) {
            return const Center(child: Text('No claims yet.'));
          }
          return ListView.separated(
            itemCount: claims.length,
            // ignore: unnecessary_underscores
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = claims[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                elevation: 2,
                child: FutureBuilder<ItemModel?>(
                  future: ItemService.instance.getItemOnce(c.itemId),
                  builder: (context, itemSnap) {
                    String itemName = 'Loading item...';
                    String itemPhotoUrl = '';
                    final item = itemSnap.data;
                    if (item != null) {
                      itemName = item.title;
                      if (item.photos.isNotEmpty) {
                        itemPhotoUrl = item.photos.first;
                      }
                    } else if (itemSnap.connectionState ==
                        ConnectionState.done) {
                      itemName = 'Item unavailable';
                    }

                    return FutureBuilder<UserModel?>(
                      future: AuthService.instance.getUserProfileCached(
                        c.claimerUid,
                      ),
                      builder: (context, userSnap) {
                        String claimerName = 'Loading user...';
                        if (userSnap.data != null) {
                          claimerName = userSnap.data?.name ?? 'Unknown User';
                        } else if (userSnap.connectionState ==
                            ConnectionState.done) {
                          claimerName = 'Unknown User';
                        }

                        return ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(claimId: c.id),
                            ),
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: itemPhotoUrl,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.image_not_supported),
                            ),
                          ),
                          title: Text(
                            claimerName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Item: $itemName'),
                              const SizedBox(height: 4),
                              _buildStatusChip(c.status),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: c.status == 'pending'
                              ? _ClaimActionButtons(claim: c)
                              : null,
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Accept/decline buttons for a single pending claim. Owns an in-flight flag so
/// rapid double-taps can't fire duplicate writes, awaits the transactional
/// service call, and surfaces success/failure to the user.
class _ClaimActionButtons extends StatefulWidget {
  final ClaimModel claim;
  const _ClaimActionButtons({required this.claim});

  @override
  State<_ClaimActionButtons> createState() => _ClaimActionButtonsState();
}

class _ClaimActionButtonsState extends State<_ClaimActionButtons> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String successMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final c = widget.claim;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.red),
          onPressed: () => _run(
            () => ClaimService.instance
                .declineClaim(claimId: c.id, itemId: c.itemId),
            'Declined',
          ),
        ),
        IconButton(
          icon: const Icon(Icons.check_rounded, color: Colors.green),
          onPressed: () => _run(
            () => ClaimService.instance
                .acceptClaim(claimId: c.id, itemId: c.itemId),
            'Accepted',
          ),
        ),
      ],
    );
  }
}
