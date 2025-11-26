import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/claim_service.dart';
import 'chat_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/report_dialog.dart';
import 'profile_page.dart';
import '../models/user_model.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
            const Center(
              child: Text(
                'You posted this item.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
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

      // --- NEW NOTIFICATION CODE STARTS HERE ---
      // Get the owner's FCM token from firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(item.ownerUid)
          .get();

      String? ownerToken;

      // Check if the data exists
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;

        if (data['fcmToken'] is String) {
          ownerToken = data['fcmToken'];
        } else if (data['fcmTokens'] is List &&
            (data['fcmTokens'] as List).isNotEmpty) {
          ownerToken = (data['fcmTokens'] as List).last.toString();
        }
      }

      if (ownerToken != null) {
        final serviceAccountJson = {
          "type": "service_account",
          "project_id": dotenv.env['FCM_PROJECT_ID'],
          "private_key_id": "5bee0dd0b3bb2351ba79014732bf2ebeb9712a54",
          "private_key":
              dotenv.env['FCM_PRIVATE_KEY']?.replaceAll('\\n', '\n') ?? "",
          "client_email": dotenv.env['FCM_CLIENT_EMAIL'],
          "client_id": "108810556853786570043",
          "auth_uri": "https://accounts.google.com/o/oauth2/auth",
          "token_uri": "https://oauth2.googleapis.com/token",
          "auth_provider_x509_cert_url":
              "https://www.googleapis.com/oauth2/v1/certs",
          "client_x509_cert_url":
              "https://www.googleapis.com/robot/v1/metadata/x509/${dotenv.env['FCM_CLIENT_EMAIL']}",
          "universe_domain": "googleapis.com",
        };

        // Get the Access Token
        final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
        final credentials = auth.ServiceAccountCredentials.fromJson(
          serviceAccountJson,
        );
        final client = await auth.clientViaServiceAccount(credentials, scopes);

        // Send the V1 Request
        final response = await client.post(
          Uri.parse(
            'https://fcm.googleapis.com/v1/projects/foundme-28322/messages:send',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "message": {
              "token": ownerToken,
              "notification": {
                "title": "Someone claimed your item!",
                "body": "Check your messages: \"${msg.trim()}\"",
              },
              "data": {
                "click_action": "FLUTTER_NOTIFICATION_CLICK",
                "type": "claim_alert",
                "claimId": claimId,
              },
              "android": {
                "priority": "high", // High priority for Realme/Xiaomi
                "notification": {"channel_id": "high_importance_channel"},
              },
            },
          }),
        );

        print("📡 FCM Response Status: ${response.statusCode}");
        print("📡 FCM Response Body: ${response.body}");

        client.close();
      } else {
        print("Owner has no token.");
      }

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
