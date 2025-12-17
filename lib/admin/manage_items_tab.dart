import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/item.dart';
import '../pages/item_detail_page.dart';
import '../services/item_service.dart';

class ManageItemsTab extends StatelessWidget {
  const ManageItemsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ItemModel>>(
      stream: ItemService.instance.adminGetAllItems(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('Database is empty.'),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final item = items[i];

            // Determine status color
            Color statusColor = Colors.grey;
            if (item.status == 'active') statusColor = Colors.green;
            if (item.status == 'pending_approval') statusColor = Colors.orange;
            if (item.status == 'closed' || item.status == 'expired')
              statusColor = Colors.red;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),

              // 1. Image Preview
              leading: item.photos.isNotEmpty
                  ? CircleAvatar(
                      radius: 24,
                      backgroundImage: CachedNetworkImageProvider(
                        item.photos.first,
                      ),
                      backgroundColor: Colors.grey[200],
                    )
                  : CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey[200],
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),

              // 2. Title
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),

              // 3. Subtitle (Status & Owner)
              subtitle: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ItemDetailPage(item: item)),
              ),

              // 4. Popup Menu (Actions)
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'delete') _showAdminDeleteDialog(context, item);
                  if (value == 'close') ItemService.instance.closeItem(item.id);
                  if (value == 'active')
                    ItemService.instance.reopenItem(item.id);
                },
                itemBuilder: (ctx) => [
                  if (item.status != 'closed' && item.status != 'expired')
                    const PopupMenuItem(
                      value: 'close',
                      child: Row(
                        children: [
                          Icon(Icons.archive, size: 18, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('Force Close / Archive'),
                        ],
                      ),
                    ),
                  if (item.status == 'closed' || item.status == 'expired')
                    const PopupMenuItem(
                      value: 'active',
                      child: Row(
                        children: [
                          Icon(Icons.refresh, size: 18, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Re-activate Post'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'Delete Permanently',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAdminDeleteDialog(BuildContext context, ItemModel item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Permanently?'),
          content: Text(
            'Are you sure you want to delete "${item.title}"? \n\nThis cannot be undone and will remove photos from storage.',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
              onPressed: () async {
                try {
                  await ItemService.instance.deleteItem(item);
                  if (context.mounted) Navigator.of(context).pop();
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
        );
      },
    );
  }
}
