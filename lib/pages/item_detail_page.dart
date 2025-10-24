import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/claim_service.dart';
import 'chat_page.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ItemDetailPage extends StatelessWidget {
  final ItemModel item;
  const ItemDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final isGuest = AuthService.instance.isGuest;
    final uid = user?.uid;
    final isOwner = uid == item.ownerUid;

    return Scaffold(
      appBar: AppBar(title: const Text('Item detail')),
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
          Text('${item.type.toUpperCase()} • ${item.category}'),
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

          // Action area
          if (isOwner)
            const Text(
              'You posted this item.',
              style: TextStyle(fontStyle: FontStyle.italic),
            )
          else if (item.status != 'active')
            const Text(
              'This post is not active.',
              style: TextStyle(fontStyle: FontStyle.italic),
            )
          else if (isGuest)
            // Guest: prompt to register
            OutlinedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Register to claim'),
              onPressed: () => Navigator.pushNamed(context, '/register'),
            )
          else
            // Signed-in user (not owner) & active: can claim
            ElevatedButton.icon(
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Claim this item'),
              onPressed: () async {
                // Ask for initial message
                final msg = await showDialog<String>(
                  context: context,
                  builder: (_) => const _InitialMessageDialog(),
                );
                if (msg == null || msg.trim().isEmpty) return;

                try {
                  final claimId = await ClaimService.instance.createClaim(
                    itemId: item.id,
                    ownerUid: item.ownerUid,
                    initialMessage: msg.trim(),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Claim request sent')),
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(claimId: claimId),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to send claim: $e')),
                  );
                }
              },
            ),
        ],
      ),
    );
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
