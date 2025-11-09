import 'package:flutter/material.dart';
import 'claims_inbox_page.dart';
import 'my_claims_page.dart';

class ClaimsPageContainer extends StatelessWidget {
  const ClaimsPageContainer({super.key});

  @override
  Widget build(BuildContext context) {
    // This widget sets up the TabBar
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Claims'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Claims Inbox'),
              Tab(text: 'My Claims'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            // The content for each tab
            ClaimsInboxPage(),
            MyClaimsPage(),
          ],
        ),
      ),
    );
  }
}
