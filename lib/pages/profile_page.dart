import 'package:flutter/material.dart';
import '../models/item.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/item_service.dart';
import 'add_item_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/report_dialog.dart';
import 'item_detail_page.dart';
import 'admin_dashboard_page.dart';

class ProfilePage extends StatelessWidget {
  final String? userId;

  const ProfilePage({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final itemService = ItemService.instance;

    // Check if this is our own profile or someone else's
    final currentUid = auth.currentUser?.uid;
    final bool isMyProfile = (userId == null || userId == currentUid);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(isMyProfile ? 'My Profile' : 'User Profile'),
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          if (isMyProfile)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Log Out',
              onPressed: () => _showLogoutDialog(context),
            ),
        ],
      ),
      body: StreamBuilder<UserModel?>(
        stream: auth.userStream(uid: userId),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!userSnapshot.hasData || userSnapshot.data == null) {
            return const Center(child: Text('User not found.'));
          }

          final user = userSnapshot.data!;

          /* return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: isMyProfile
                        ? () => _showImageSourceDialog(context)
                        : null,
                    child: CircleAvatar(
                      radius: 40,
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
                  // ONLY show "Edit" button on our own profile
                  if (isMyProfile)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () =>
                          _showEditProfileDialog(context, user.name),
                    ),
                ],
              ),
              const Divider(height: 32),

              Text(
                isMyProfile
                    ? 'My Posts (Report History)'
                    : "${user.name}'s Posts",
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          isMyProfile
                              ? 'You have not posted any items yet.'
                              : 'This user has no posts.',
                        ),
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
                            if (isMyProfile) {
                              // If its my profile, go to edit page
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddItemPage(editing: item),
                                ),
                              );
                            } else {
                              // If its someone else's profile, go to the read-only detail page
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ItemDetailPage(item: item),
                                ),
                              );
                            }
                          },
                          trailing: isMyProfile
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      _showDeletePostDialog(context, item),
                                )
                              : null,
                        ),
                      );
                    },
                  );
                },
              ),
              const Divider(height: 32),

              if (isMyProfile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user.role == 'admin') ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.admin_panel_settings),
                        label: const Text('Go to Admin Panel'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AdminDashboardPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

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
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => ReportDialog(
                        reportedUid: user.uid, // Report the user
                      ),
                    );
                  },
                  child: const Text('Report User'),
                ),
            ],
          ); */
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // 1. HEADER SECTION (Profile Pic & Name)
                _buildProfileHeader(context, user, isMyProfile),

                // 2. STATS SECTION (Rating & Counts)
                _buildStatsSection(user),

                const Divider(thickness: 1, height: 30),

                // 3. ADMIN BUTTON (If applicable)
                if (isMyProfile && user.role == 'admin')
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Card(
                      color: Colors.indigo[50],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.indigo.shade100),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.admin_panel_settings,
                          color: Colors.indigo[900],
                        ),
                        title: Text(
                          "Admin Dashboard",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo[900],
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminDashboardPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // 4. ITEMS LIST TITLE
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      Text(
                        isMyProfile ? 'My Activity' : 'Posted Items',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (!isMyProfile)
                        TextButton.icon(
                          icon: const Icon(Icons.flag_outlined, size: 16),
                          label: const Text("Report User"),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) =>
                                  ReportDialog(reportedUid: user.uid),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                // 5. ITEMS LIST
                StreamBuilder<List<ItemModel>>(
                  stream: itemService.myItems(user.uid),
                  builder: (context, itemSnapshot) {
                    if (itemSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (!itemSnapshot.hasData || itemSnapshot.data!.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 50,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                isMyProfile
                                    ? 'No items posted yet.'
                                    : 'This user hasn\'t posted anything.',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final items = itemSnapshot.data!;
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        return _buildItemCard(
                          context,
                          items[index],
                          isMyProfile,
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 40), // Bottom padding
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(
    BuildContext context,
    UserModel user,
    bool isMyProfile,
  ) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      child: Column(
        children: [
          // Profile Image with Edit Badge
          Center(
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(4), // White border
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: (user.photoURL != null)
                        ? CachedNetworkImageProvider(user.photoURL!)
                        : null,
                    child: (user.photoURL == null)
                        ? Icon(Icons.person, size: 50, color: Colors.grey[400])
                        : null,
                  ),
                ),
                if (isMyProfile)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: () => _showImageSourceDialog(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Name and Verification Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                user.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (user.isVerified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified, color: Colors.blue, size: 20),
              ],
            ],
          ),

          Text(
            user.email,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),

          const SizedBox(height: 12),

          if (isMyProfile)
            OutlinedButton.icon(
              onPressed: () => _showEditProfileDialog(context, user.name),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text("Edit Name"),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(UserModel user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            "Rating",
            user.averageRating.toStringAsFixed(1),
            Icons.star,
            Colors.amber,
          ),
          _buildStatItem(
            "Reviews",
            "${user.ratingCount}",
            Icons.rate_review,
            Colors.blue,
          ),
          _buildStatItem(
            "Status",
            user.isVerified ? "Verified" : "Unverified",
            Icons.shield,
            user.isVerified ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    ItemModel item,
    bool isMyProfile,
  ) {
    // Define color for status chip
    Color statusColor;
    switch (item.status) {
      case 'active':
        statusColor = Colors.blue;
        break;
      case 'resolved':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isMyProfile) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddItemPage(editing: item)),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ItemDetailPage(item: item)),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 1. Thumbnail Image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.photos.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.photos.first,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 70,
                        height: 70,
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.image_not_supported,
                          color: Colors.grey,
                        ),
                      ),
              ),
              const SizedBox(width: 16),

              // 2. Info Column
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.category,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor.withOpacity(0.5)),
                      ),
                      child: Text(
                        item.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Edit/Delete Icon
              if (isMyProfile)
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showDeletePostDialog(context, item),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImageSourceDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Update Profile Picture",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.camera_alt, color: Colors.white),
                  ),
                  title: const Text('Take Photo'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAndUploadImage(context, ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.purpleAccent,
                    child: Icon(Icons.photo_library, color: Colors.white),
                  ),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAndUploadImage(context, ImageSource.gallery);
                  },
                ),
              ],
            ),
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
            decoration: const InputDecoration(
              labelText: 'Display Name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
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
              child: const Text('Delete'),
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
          content: const Text('Are you sure you want to log out of FoundMe?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                await AuthService.instance.logout();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Log Out'),
            ),
          ],
        );
      },
    );
  }
}
