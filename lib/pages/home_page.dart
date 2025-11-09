import 'package:flutter/material.dart';
// import '../services/auth_service.dart';
import 'feed_page.dart';
import 'add_item_page.dart';
import 'claims_inbox_page.dart';
import 'my_claims_page.dart';
import 'profile_page.dart';
import '../services/notifications_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'map_view_page.dart';
import 'claims_page_container.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int idx = 0;
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.init();

    _messageSubscription = NotificationService.instance.foregroundMessages
        .listen((RemoteMessage message) {
          if (mounted && message.notification != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message.notification!.title ?? 'New Message'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const FeedPage(),
      const MapViewPage(),
      const ClaimsPageContainer(),
      const ProfilePage(),
    ];
    return Scaffold(
      body: pages[idx],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) => setState(() => idx = i),

        type: BottomNavigationBarType.fixed,

        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Map'),
          BottomNavigationBarItem(
            icon: Icon(Icons.handshake_outlined),
            label: 'Claims',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: idx == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddItemPage(editing: null)),
              ),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

/*class _ClaimsHubPage extends StatelessWidget {
  // ignore: unused_element_parameter
  const _ClaimsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Claims')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Claims inbox (for owners)'),
              subtitle: const Text('See requests on items you posted'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ClaimsInboxPage()),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.outbox_outlined),
              title: const Text('My claims'),
              subtitle: const Text('Requests you sent to others'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyClaimsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
} */
