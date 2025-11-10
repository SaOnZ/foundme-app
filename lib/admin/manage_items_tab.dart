import 'package:flutter/material.dart';
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
          return const Center(child: Text('No items found.'));
        }

        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                title: Text(item.title),
                subtitle: Text('By: ${item.ownerUid}\nStatus: ${item.status}'),
                isThreeLine: true,

                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ItemDetailPage(item: item)),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  tooltip: 'Delete Item Permanently',
                  onPressed: () => _showAdminDeleteDialog(context, item),
                ),
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
          title: const Text('Delete post?'),
          content: Text(
            'Are you sure you want to permanently delete "${item.title}"? This will also delete its photos and cannot be undone.',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete Permanently'),
              onPressed: () async {
                try {
                  // calls the deleteItem function
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
