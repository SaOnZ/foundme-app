import 'dart:async';
import 'package:flutter/material.dart';
import '../services/item_service.dart';
import '../models/item.dart';
import 'item_detail_page.dart';
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

  // How many items to request from the feed; grows when the user taps
  // "Load more" so the query stays bounded but isn't permanently capped at 50.
  int _limit = 50;
  static const _pageSize = 50;

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
          // Lost / Found type filter (previously a dead, UI-less field).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: types.map((t) {
                final selected = type == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t == 'ALL' ? 'All' : t),
                    selected: selected,
                    onSelected: (_) => setState(() => type = t),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Feed
          Expanded(
            child: StreamBuilder<List<ItemModel>>(
              stream: ItemService.instance.latestActive(limit: _limit),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var items = snap.data!;
                // If the raw page came back full, there may be more to load.
                final canLoadMore = items.length >= _limit;

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
                  // Uses the per-item cached searchBlob so we don't rebuild a
                  // lowercased string for every item on every keystroke/compare.
                  items = items
                      .where((it) => it.searchBlob.contains(q))
                      .toList();
                  int score(String hay) =>
                      (hay.startsWith(q) ? 2 : 0) + (hay.contains(q) ? 1 : 0);
                  items.sort(
                    (a, b) => score(b.searchBlob).compareTo(score(a.searchBlob)),
                  );
                }

                if (items.isEmpty) {
                  return const Center(
                    child: Text('No results. Tap + to add one.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: items.length + (canLoadMore ? 1 : 0),
                  // ignore: unnecessary_underscores
                  separatorBuilder: (_, __) => const SizedBox(height: 0),
                  itemBuilder: (_, i) {
                    // Trailing "Load more" row.
                    if (i >= items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _limit += _pageSize),
                          child: const Text('Load more'),
                        ),
                      );
                    }
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

}
