import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/item_service.dart';
import '../models/item.dart';
import '../models/status.dart';

class ApprovalsTab extends StatelessWidget {
  const ApprovalsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ItemModel>>(
      stream: ItemService.instance.getPendingApprovalItems(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Could not load pending items.',
              style: TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.task_alt, size: 80, color: Colors.green[100]),
                const SizedBox(height: 16),
                Text(
                  "All Clear!",
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "No pending items to review.",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.only(bottom: 16),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.photos.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.photos.first,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey[300],
                          child: const Icon(Icons.image_not_supported),
                        ),
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "Type: ${item.type.toUpperCase()} • Cat: ${item.category}",
                ),
                children: [
                  Container(
                    color: Colors.grey[50],
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "DESCRIPTION",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(item.desc),
                        const SizedBox(height: 16),

                        const Text(
                          "STUDENT VERIFICATION",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // User Matric Fetcher — fetches once and handles
                        // missing/errored verification data.
                        _VerificationInfo(ownerUid: item.ownerUid),
                        const SizedBox(height: 20),

                        // Action Buttons (with confirmation + error handling)
                        _ApprovalActions(itemId: item.id),
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
}

/// Fetches the poster's public name (/users) and sensitive matric data
/// (/verifications) once in initState — so it doesn't refetch on every
/// ExpansionTile rebuild — and surfaces load errors / missing verification.
class _VerificationInfo extends StatefulWidget {
  final String ownerUid;
  const _VerificationInfo({required this.ownerUid});

  @override
  State<_VerificationInfo> createState() => _VerificationInfoState();
}

class _VerificationInfoState extends State<_VerificationInfo> {
  late final Future<List<DocumentSnapshot>> _future;

  @override
  void initState() {
    super.initState();
    _future = Future.wait([
      FirebaseFirestore.instance.collection('users').doc(widget.ownerUid).get(),
      FirebaseFirestore.instance
          .collection('verifications')
          .doc(widget.ownerUid)
          .get(),
    ]);
  }

  /// Fetches a short-lived signed URL for the matric card on demand (admin
  /// only, generated by the getMatricCardUrl function) and shows it.
  Future<void> _viewId(BuildContext context) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getMatricCardUrl')
          .call({'uid': widget.ownerUid});
      final url = (res.data as Map)['url'] as String?;
      if (url == null || !context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500),
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (c, _) => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (c, _, __) => const SizedBox(
                  height: 200,
                  child: Center(child: Text('Could not load ID')),
                ),
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load ID image.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DocumentSnapshot>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Text(
            'Could not load verification details.',
            style: TextStyle(color: Colors.red, fontSize: 12),
          );
        }
        if (!snap.hasData) return const LinearProgressIndicator();

        final userData = snap.data![0].data() as Map<String, dynamic>?;
        final verifData = snap.data![1].data() as Map<String, dynamic>?;
        final hasCard = verifData?['matricCardPath'] != null;
        final name = userData?['name'] ?? 'Unknown';
        final matricNo = verifData?['matricNumber'] ?? 'N/A';
        final missingVerification = verifData == null;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: missingVerification
                  ? Colors.orange.shade200
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blue[50],
                child: const Icon(Icons.person, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      matricNo,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    if (missingVerification)
                      const Text(
                        '⚠ No verification on file',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (hasCard)
                TextButton.icon(
                  icon: const Icon(Icons.badge, size: 16),
                  label: const Text("View ID"),
                  onPressed: () => _viewId(context),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Approve/Reject buttons with a confirmation on reject, an in-flight guard
/// against double-taps, and user-facing success/error feedback.
class _ApprovalActions extends StatefulWidget {
  final String itemId;
  const _ApprovalActions({required this.itemId});

  @override
  State<_ApprovalActions> createState() => _ApprovalActionsState();
}

class _ApprovalActionsState extends State<_ApprovalActions> {
  bool _busy = false;

  Future<void> _setStatus(String status, String successMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ItemService.instance.setItemStatus(widget.itemId, status);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this post?'),
        content: const Text('The poster will not see their item published.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _setStatus(ItemStatus.rejected, 'Post rejected');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.close),
            label: const Text("Reject"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            onPressed: _confirmReject,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text("Approve"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _setStatus(ItemStatus.active, 'Post approved'),
          ),
        ),
      ],
    );
  }
}
