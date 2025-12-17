import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart'; // Needed for date formatting
import '../services/log_service.dart';

class DashboardOverviewTab extends StatelessWidget {
  const DashboardOverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===================================================
          // PART 1: STATISTICS (Charts & Numbers)
          // ===================================================
          const Text(
            "System Statistics",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('items').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();

              final allDocs = snapshot.data!.docs;
              final total = allDocs.length;
              final pending = allDocs
                  .where((d) => d['status'] == 'pending_approval')
                  .length;
              final lost = allDocs.where((d) => d['type'] == 'lost').length;
              final found = allDocs.where((d) => d['type'] == 'found').length;

              // Calculate Percentages safely
              final double lostPercent = total == 0 ? 0 : (lost / total) * 100;
              final double foundPercent = total == 0
                  ? 0
                  : (found / total) * 100;

              return Column(
                children: [
                  // A. Summary Cards
                  Row(
                    children: [
                      _StatCard(
                        title: "Total Posts",
                        value: "$total",
                        icon: Icons.folder_copy,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        title: "Pending",
                        value: "$pending",
                        icon: Icons.hourglass_top,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // B. Pie Chart
                  Container(
                    height: 220,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: [
                                PieChartSectionData(
                                  value: lost.toDouble(),
                                  color: Colors.red[400],
                                  title: '${lostPercent.toInt()}%',
                                  radius: 45,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                PieChartSectionData(
                                  value: found.toDouble(),
                                  color: Colors.green[400],
                                  title: '${foundPercent.toInt()}%',
                                  radius: 45,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Legend(
                              color: Colors.red[400]!,
                              text: "Lost ($lost)",
                            ),
                            const SizedBox(height: 8),
                            _Legend(
                              color: Colors.green[400]!,
                              text: "Found ($found)",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 30),

          // ===================================================
          // PART 2: LOG MONITORING (The Missing Part!)
          // ===================================================
          const Text(
            "Live Activity Log",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            "Most recent database events",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            // Fetch the last 10 items added/updated, ordered by time
            stream: LogService.instance.getRecentLogs(),
            //FirebaseFirestore.instance.collection('items').orderBy('postedAt', descending: true).limit(10).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Text('Error loading logs: ${snapshot.error}');
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final logs = snapshot.data!.docs;

              if (logs.isEmpty) return const Text("No activity logs yet.");

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListView.separated(
                  shrinkWrap: true, // Important: Allows list inside scrollview
                  physics:
                      const NeverScrollableScrollPhysics(), // Disable internal scrolling
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final data = logs[index].data() as Map<String, dynamic>;

                    // Parse Data
                    final title = data['title'] ?? 'System Event';
                    final details = data['details'] ?? '';
                    final status = data['status'] ?? 'info';
                    //                   final type = data['type'] ?? 'general';
                    final Timestamp? ts =
                        data['timestamp']; // LogService uses 'timestamp'

                    final DateTime time = ts?.toDate() ?? DateTime.now();
                    final timeString = DateFormat('MMM dd, HH:mm').format(time);

                    // Determine Status Icon & Color
                    IconData statusIcon = Icons.info;
                    Color statusColor = Colors.grey;

                    if (status == 'active' || status == 'approved') {
                      statusIcon = Icons.check_circle;
                      statusColor = Colors.green;
                    } else if (status == 'pending') {
                      statusIcon = Icons.pending;
                      statusColor = Colors.orange;
                    } else if (status == 'rejected' ||
                        status == 'closed' ||
                        status == 'banned') {
                      statusIcon = Icons.cancel;
                      statusColor = Colors.red;
                    }

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withOpacity(0.1),
                        child: Icon(statusIcon, color: statusColor, size: 20),
                      ),
                      title: Text(
                        title, // SHows "Item Closed", "User Banned", etc
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        "$details\n$timeString",
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 50), // Bottom padding
        ],
      ),
    );
  }
}

// --- HELPER WIDGETS ---

class _StatCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(title, style: TextStyle(color: color.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
