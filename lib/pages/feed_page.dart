import 'dart:async';
import 'package:flutter/material.dart';
import '../services/item_service.dart';
import '../models/item.dart';
import 'item_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/feed_item_card.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String q = '';
  String category = 'All';
  final cats = const [
    'All',
    'Electronics',
    'Wallets & IDs',
    'Keys',
    'Bags & Luggage',
    'Clothing & Wearables',
    'Books & Stationery',
    'Water Bottles',
    'Sports & Hobby',
    'Others',
  ];

  String type = 'ALL';
  final types = const ['ALL', 'Lost', 'Found'];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Lost & Found')),
      body: Column(
        children: [
          // Search + category filter
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        setState(() => q = v.trim().toLowerCase());
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search title / description / tags…',
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => q = '');
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: category,
                  items: cats
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => category = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Feed
          Expanded(
            child: StreamBuilder<List<ItemModel>>(
              stream: ItemService.instance.latestActive(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var items = snap.data!;

                // Client-side filters (fine for campus-scale data)
                if (type != 'ALL') {
                  items = items
                      .where((it) => it.type == type.toLowerCase())
                      .toList();
                }
                if (category != 'All') {
                  items = items.where((it) => it.category == category).toList();
                }
                if (q.isNotEmpty) {
                  items = items.where((it) {
                    final hay = '${it.title} ${it.desc} ${it.tags.join(" ")}'
                        .toLowerCase();
                    return hay.contains(q);
                  }).toList();
                  int score(String hay) =>
                      (hay.startsWith(q) ? 2 : 0) + (hay.contains(q) ? 1 : 0);
                  items.sort((a, b) {
                    final ha = '${a.title} ${a.desc} ${a.tags.join(" ")}'
                        .toLowerCase();
                    final hb = '${b.title} ${b.desc} ${b.tags.join(" ")}'
                        .toLowerCase();
                    return score(hb).compareTo(score(ha));
                  });
                }

                if (items.isEmpty) {
                  return const Center(
                    child: Text('No results. Tap + to add one.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: items.length,
                  // ignore: unnecessary_underscores
                  separatorBuilder: (_, __) => const SizedBox(height: 0),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FeedItemCard(
                        item: it,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ItemDetailPage(item: it),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper: Convert Timestamp to "time Ago" string
  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
