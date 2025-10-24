import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/claim_service.dart';
import '../models/claim.dart';
import 'chat_page.dart';

class ClaimsInboxPage extends StatelessWidget {
  const ClaimsInboxPage({super.key});

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
              return ListTile(
                title: Text(
                  c.message.isEmpty ? '(no message)' : c.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Item: ${c.itemId}\nBy: ${c.claimerUid}\nStatus: ${c.status}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Accept',
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: c.status == 'pending'
                          ? () => ClaimService.instance.setClaimStatus(
                              c.id,
                              'accepted',
                            )
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Reject',
                      icon: const Icon(Icons.cancel_outlined),
                      onPressed: c.status == 'pending'
                          ? () => ClaimService.instance.setClaimStatus(
                              c.id,
                              'rejected',
                            )
                          : null,
                    ),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatPage(claimId: c.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
