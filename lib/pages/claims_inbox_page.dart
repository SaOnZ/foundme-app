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
                child: StreamBuilder<ItemModel>(
                  stream: ItemService.instance.getItemStream(c.itemId),
                  builder: (context, itemSnap) {
                    String itemName = 'Loading item...';
                    String itemPhotoUrl = '';
                    if (itemSnap.hasData) {
                      itemName = itemSnap.data!.title;
                      if (itemSnap.data!.photos.isNotEmpty) {
                        itemPhotoUrl = itemSnap.data!.photos.first;
                      }
                    }

                    return StreamBuilder<UserModel?>(
                      stream: AuthService.instance.userStream(
                        uid: c.claimerUid,
                      ),
                      builder: (context, userSnap) {
                        String claimerName = 'Loading user...';
                        if (userSnap.hasData) {
                          claimerName = userSnap.data?.name ?? 'Unknow User';
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
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => ClaimService.instance
                                          .setClaimStatus(c.id, 'declined'),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.green,
                                      ),
                                      onPressed: () => ClaimService.instance
                                          .setClaimStatus(c.id, 'accepted'),
                                    ),
                                  ],
                                )
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
