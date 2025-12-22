import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../admin/dashboard_overview_tab.dart';
import '../admin/approvals_tab.dart';
import '../admin/manage_items_tab.dart';
import '../admin/manage_users_tab.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    await AuthService.instance.logout();

    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Admin Console',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Logout',
              onPressed: () => _handleLogout(context),
            ),
            const SizedBox(width: 8),
          ],

          bottom: const TabBar(
            labelColor: Colors.amberAccent,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.amberAccent,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
              Tab(icon: Icon(Icons.verified_user_outlined), text: 'Approvals'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'All Items'),
              Tab(icon: Icon(Icons.people_outline), text: 'Users'),
            ],
          ),
        ),
        backgroundColor: Colors.grey[100],
        body: const TabBarView(
          children: [
            DashboardOverviewTab(),
            ApprovalsTab(),
            ManageItemsTab(),
            ManageUsersTab(),
          ],
        ),
      ),
    );
  }
}
