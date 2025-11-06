import 'package:flutter/material.dart';
import '../services/report_service.dart';

class ReportDialog extends StatefulWidget {
  final String? reportedItemId;
  final String? reportedUid;

  const ReportDialog({super.key, this.reportedItemId, this.reportedUid});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String _selectedReason = 'Spam or Scam';
  bool _isLoading = false;
  final _reasons = [
    'Spam or Scam',
    'Fake Item / Misleading Info',
    'Harrassment or Hate Speech',
    'Fraudelent User',
    'Other',
  ];

  Future<void> _submitReport() async {
    setState(() => _isLoading = true);
    try {
      await ReportService.instance.submitReport(
        reason: _selectedReason,
        reportedItemId: widget.reportedItemId,
        reportedUid: widget.reportedUid,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Thank you for your help!'),
        ),
      );
      Navigator.of(context).pop(); // close the dialog
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Content'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Why are you reporting this?'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedReason,
            items: _reasons.map((reason) {
              return DropdownMenuItem(value: reason, child: Text(reason));
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedReason = value);
              }
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitReport,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Submit Report'),
        ),
      ],
    );
  }
}
