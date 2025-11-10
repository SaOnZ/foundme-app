import 'package:cached_network_image/cached_network_image.dart';
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

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, i) {
            final user = users[i];
            final bool isMe = (user.uid == adminUid);
            final bool isAlsoAdmin = (user.role == 'admin');

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: (user.photoURL != null)
                      ? CachedNetworkImageProvider(user.photoURL!)
                      : null,
                  child: (user.photoURL == null)
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(user.name),
                subtitle: Text(user.email),
                trailing: isMe
                    ? const Text(
                        '(You)',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      )
                    : TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: isAlsoAdmin
                              ? Colors.grey
                              : Colors.red,
                        ),
                        onPressed: isAlsoAdmin
                            ? null
                            : () => _showDisableDialog(context, user),
                        child: Text(isAlsoAdmin ? 'Admin' : 'Disable'),
                      ),
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
            'Are you sure you want to disable ${user.name}? They will no longer be able to log in.',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Disable'),
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
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('An unknown error occured: $e')));
      }
    }
  }
}
