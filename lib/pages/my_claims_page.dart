import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/claim_service.dart';
import '../models/claim.dart';
import 'chat_page.dart';
import '../widgets/rating_dialog.dart';

class MyClaimsPage extends StatelessWidget {
  const MyClaimsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Guest/signed-out users: block wih a friendly prompt
    if (AuthService.instance.isGuest ||
        AuthService.instance.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My claims')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please sign in to view your claims.'),
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

    final me = AuthService.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('My claims')),
      body: StreamBuilder<List<ClaimModel>>(
        stream: ClaimService.instance.myClaims(me),
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

              Widget? trailingButton;

              // Show "Rate" button if the claim is completed and user hasn't reviewed yet
              if (c.status == 'closed' && !c.claimerHasReviewed) {
                trailingButton = TextButton(
                  child: const Text('Rate Owner'),
                  onPressed: () async {
                    // Get the owner's name to display in the dialog
                    final owner = await AuthService.instance.getUserProfile(
                      c.ownerUid,
                    );
                    final ownerName = owner?.name ?? 'the Owner';

                    if (!context.mounted) return;

                    // Show the rating dialog
                    showDialog(
                      context: context,
                      builder: (_) => RatingDialog(
                        claimId: c.id,
                        roleToReview: 'owner', // The claimer rates the owner
                        personToReviewName: ownerName,
                      ),
                    );
                  },
                );
              }

              return ListTile(
                title: Text('Item: ${c.itemId}'),
                subtitle: Text('Status: ${c.status}\n${c.message}'),
                isThreeLine: true,
                trailing: trailingButton,
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
