import 'package:flutter/material.dart';
import '../services/item_service.dart';
import '../services/auth_service.dart';
import '../models/item.dart';
import 'add_item_page.dart';
import 'item_detail_page.dart';

class MyPostsPage extends StatelessWidget {
  const MyPostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Block guest/ signed-out users to avoid currentUser! crash
    if (AuthService.instance.isGuest ||
        AuthService.instance.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My posts')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please sign in to view your posts.'),
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

    final uid = AuthService.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('My posts')),
      body: StreamBuilder<List<ItemModel>>(
        stream: ItemService.instance.myItems(uid),
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
              child: Text('You have not posted anything yet'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final it = items[i];
              final img = it.photos.isNotEmpty
                  ? Image.network(
                      it.photos.first,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    )
                  : const SizedBox(width: 80, height: 80);

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: img,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _StatusChip(status: it.status),
                  ],
                ),
                subtitle: Text(
                  '${it.type.toUpperCase()} • ${it.category}\n${it.locationText}',
                  maxLines: 2,
                ),
                isThreeLine: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ItemDetailPage(item: it)),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddItemPage(editing: it),
                        ),
                      );
                    } else if (v == 'close') {
                      await ItemService.instance.closeItem(it.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Closed')));
                    } else if (v == 'reopen') {
                      await ItemService.instance.reopenItem(it.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Reopened')));
                    } else if (v == 'delete') {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete post'),
                          content: const Text(
                            'This will remove the post and its photos. Continue?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ItemService.instance.deleteItem(it);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Deleted')),
                        );
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (it.status == 'active')
                      const PopupMenuItem(
                        value: 'close',
                        child: Text('Mark as closed'),
                      ),
                    if (it.status != 'active')
                      const PopupMenuItem(
                        value: 'reopen',
                        child: Text('Reopen'),
                      ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Color bg;
    switch (status) {
      case 'active':
        bg = colors.primaryContainer;
        break;
      case 'closed':
        bg = colors.surfaceContainerHighest;
        break;
      case 'matched':
        bg = colors.tertiaryContainer;
        break;
      default:
        bg = colors.surfaceContainerHighest;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status, style: const TextStyle(fontSize: 12)),
    );
  }
}
