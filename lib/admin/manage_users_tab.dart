import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class ManageUsersTab extends StatelessWidget {
  const ManageUsersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final adminUid = AuthService.instance.currentUser?.uid;

    return StreamBuilder<List<UserModel>>(
      stream: AuthService.instance.adminGetAllUsers(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snap.data!;

        if (users.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No users found.'),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final user = users[i];
            final bool isMe = (user.uid == adminUid);
            final bool isAdmin = (user.role == 'admin');

            final bool isDisabled = user.isDisabled;

            return ListTile(
              enabled: !isDisabled,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),

              // 1. Smart Avatar (Photo or Initials)
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: isDisabled
                    ? Colors.grey[300]
                    : (isAdmin ? Colors.indigo[100] : Colors.grey[200]),
                backgroundImage:
                    (user.photoURL != null && user.photoURL!.isNotEmpty)
                    ? CachedNetworkImageProvider(user.photoURL!)
                    : null,
                child: (user.photoURL == null || user.photoURL!.isEmpty)
                    ? Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: isDisabled
                              ? Colors.grey
                              : (isAdmin ? Colors.indigo : Colors.grey[800]),
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),

              // 2. Name & Email
              title: Row(
                children: [
                  Text(
                    user.name + (isMe ? ' (You)' : ''),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: isDisabled
                          ? TextDecoration.lineThrough
                          : null,
                      color: isDisabled ? Colors.grey : Colors.black,
                    ),
                  ),
                  if (isDisabled)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'BANNED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[800],
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.email, style: const TextStyle(fontSize: 12)),
                  if (isAdmin)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ADMIN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),

              // 3. Action Menu (Disable / Info)
              trailing: isMe
                  ? null // You can't disable yourself
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'disable')
                          _showDisableDialog(context, user);
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          enabled: !isAdmin, // Cannot disable other admins
                          value: 'disable',
                          child: Row(
                            children: [
                              Icon(
                                Icons.block,
                                color: (isAdmin || isDisabled)
                                    ? Colors.grey
                                    : Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isDisabled
                                    ? 'Already Disabled'
                                    : 'Disable Account',
                                style: TextStyle(
                                  color: (isAdmin || isDisabled)
                                      ? Colors.grey
                                      : Colors.red,
                                ),
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

  void _showDisableDialog(BuildContext context, UserModel user) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Disable User?'),
          content: Text(
            'Are you sure you want to disable ${user.name}? They will no longer be able to log in to the app.',
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
              child: const Text('Disable User'),
              onPressed: () async {
                await _disableUser(context, user.uid);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _disableUser(BuildContext context, String uid) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('disableUser');
      await callable.call({'uid': uid});

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'disabled': true,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User disabled successfully.')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.message ?? "Failed to disable user"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unknown error occured: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
