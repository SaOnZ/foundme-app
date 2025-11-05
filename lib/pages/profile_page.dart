import 'package:flutter/material.dart';
import '../models/item.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/item_service.dart';
import 'add_item_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final itemService = ItemService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: StreamBuilder<UserModel?>(
        stream: auth.userStream(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!userSnapshot.hasData || userSnapshot.data == null) {
            return const Center(child: Text('User not found.'));
          }

          final user = userSnapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () => _showImageSourceDialog(context),
                    child: CircleAvatar(
                      radius: 40,
                      // Show the user;s image if it exists, otherwise show placeholder
                      backgroundImage: (user.photoURL != null)
                          ? CachedNetworkImageProvider(user.photoURL!)
                          : null,
                      child: (user.photoURL == null)
                          ? const Icon(Icons.person, size: 40)
                          : null,
                    ),
                  ),

                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(user.email),

                        const SizedBox(height: 8),
                        if (user.ratingCount > 0)
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                user.averageRating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(${user.ratingCount} ${user.ratingCount == 1 ? "review" : "reviews"})',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          )
                        else
                          const Text(
                            'No reviews yet',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditProfileDialog(context, user.name),
                  ),
                ],
              ),
              const Divider(height: 32),

              Text(
                'My Posts (Report History)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),

              StreamBuilder<List<ItemModel>>(
                stream: itemService.myItems(user.uid),
                builder: (context, itemSnapshot) {
                  if (itemSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!itemSnapshot.hasData || itemSnapshot.data!.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('You have not posted any items yet.'),
                      ),
                    );
                  }

                  final items = itemSnapshot.data!;

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        child: ListTile(
                          title: Text(item.title),
                          subtitle: Text(
                            'Status: ${item.status} (${item.type})',
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddItemPage(editing: item),
                              ),
                            );
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                _showDeletePostDialog(context, item),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const Divider(height: 32),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  _showLogoutDialog(context);
                },
                child: const Text('Log Out'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showImageSourceDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        // use ctx to avoid conflict with context
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo (Camera)'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // Pass the context to the next function
                  _pickAndUploadImage(context, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // Pass the context to the next function
                  _pickAndUploadImage(context, ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Handles picking, uploading, and error handling
  Future<void> _pickAndUploadImage(
    BuildContext context,
    ImageSource source,
  ) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);

    if (file != null) {
      // Check if the widget is still mounted before showing SnackBar
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading image...')));

      try {
        await AuthService.instance.updateProfilePicture(file);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated!')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  void _showEditProfileDialog(BuildContext context, String currentName) {
    final nameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Profile'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty) {
                  try {
                    await AuthService.instance.updateDisplayName(newName);
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeletePostDialog(BuildContext context, ItemModel item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Post?'),
          content: Text(
            'Are you sure you want to delete the post "${item.title}"? This cannot be undone.',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
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

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log Out?'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Log Out'),
              onPressed: () async {
                await AuthService.instance.logout();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
