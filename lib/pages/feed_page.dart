import 'dart:async';
import 'package:flutter/material.dart';
import '../services/item_service.dart';
import '../models/item.dart';
import 'item_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
    'General',
    'Electronics',
    'Documents',
    'Clothing',
    'Accessories',
    'Cards',
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
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  // ignore: unnecessary_underscores
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final img = it.photos.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: it.photos.first,
                            height: 88,
                            width: 88,
                            fit: BoxFit.cover,
                            // Show a loading spinner
                            placeholder: (context, url) => Container(
                              height: 88,
                              width: 88,
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            // Show and error icon if it fails
                            errorWidget: (context, url, error) => Container(
                              height: 88,
                              width: 88,
                              color: Colors.grey[200],
                              child: const Icon(Icons.error, color: Colors.red),
                            ),
                          )
                        : const SizedBox(width: 88, height: 88);

                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: img,
                      ),
                      title: Text(
                        it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${it.type.toUpperCase()} • ${it.category}\n${it.locationText}',
                        maxLines: 2,
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ItemDetailPage(item: it),
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
