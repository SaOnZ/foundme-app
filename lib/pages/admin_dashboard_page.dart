import 'package:flutter/material.dart';
import '../admin/manage_items_tab.dart';
import '../admin/manage_users_tab.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list_alt), text: 'Manage Items'),
              Tab(icon: Icon(Icons.people), text: 'Manage Users'),
            ],
          ),
        ),
        body: const TabBarView(children: [ManageItemsTab(), ManageUsersTab()]),
      ),
    );
  }
}
