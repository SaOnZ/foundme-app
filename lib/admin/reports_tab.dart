import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/report_service.dart';

/// Admin view of pending abuse reports. Previously reports were written to the
/// `reports` collection but had no console surface, so they were never seen.
class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: ReportService.instance.pendingReports(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error loading reports: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final reports = snap.data!;
        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flag_outlined, size: 64, color: Colors.green[200]),
                const SizedBox(height: 12),
                const Text('No pending reports.'),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _ReportCard(doc: reports[i]),
        );
      },
    );
  }
}

class _ReportCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  const _ReportCard({required this.doc});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;

  Future<void> _resolve(String status, String successMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ReportService.instance.resolveReport(widget.doc.id, status: status);
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

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data() as Map<String, dynamic>;
    final reason = (data['reason'] ?? '').toString();
    final reportedItemId = data['reportedItemId'] as String?;
    final reportedUid = data['reportedUid'] as String?;
    final reporterUid = (data['reporterUid'] ?? 'unknown').toString();
    final ts = data['createdAt'] as Timestamp?;
    final when = ts?.toDate();

    final target = reportedItemId != null
        ? 'Item: $reportedItemId'
        : (reportedUid != null ? 'User: $reportedUid' : 'Unknown target');

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    target,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(reason.isEmpty ? '(no reason given)' : reason),
            const SizedBox(height: 6),
            Text(
              'Reported by: $reporterUid'
              '${when != null ? ' • ${when.toLocal()}' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _resolve('dismissed', 'Report dismissed'),
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _resolve('resolved', 'Report resolved'),
                    child: const Text('Mark resolved'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
