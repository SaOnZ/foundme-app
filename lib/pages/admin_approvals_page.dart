import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/item_service.dart';
import '../models/item.dart';

class AdminApprovalsPage extends StatelessWidget {
  const AdminApprovalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Approvaks')),
      body: StreamBuilder<List<ItemModel>>(
        stream: ItemService.instance.getPendingApprovalItems(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final items = snapshot.data!;

          if (items.isEmpty) {
            return const Center(child: Text('No pending approvals.'));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _ApprovalCard(item: item);
            },
          );
        },
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final ItemModel item;
  const _ApprovalCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item info
            Row(
              children: [
                if (item.photos.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: item.photos.first,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        item.desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Type: ${item.type} • Cat: ${item.category}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),

            // User Matric Info (Fetch from Users Collection)
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(item.ownerUid)
                  .get(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) return const LinearProgressIndicator();
                final userData = userSnap.data!.data() as Map<String, dynamic>?;
                final matricUrl = userData?['matricCardUrl'];
                final matricNo = userData?['matricNumber'] ?? 'Unknown';
                final name = userData?['name'] ?? 'Unknown';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "posted By:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text("$name ($matricNo)"),
                      subtitle: const Text("Tap to view Matric Card"),
                      trailing: const Icon(Icons.visibility),
                      onTap: () {
                        if (matricUrl != null) {
                          _showMatricDialog(context, matricUrl);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "No matric card image found for this user.",
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 10),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: const Text("Reject"),
                    onPressed: () async {
                      await ItemService.instance.setItemStatus(
                        item.id,
                        'rejected',
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text("Approve"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    onPressed: () async {
                      await ItemService.instance.setItemStatus(
                        item.id,
                        'active',
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMatricDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(imageUrl: url),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        ),
      ),
    );
  }
}
