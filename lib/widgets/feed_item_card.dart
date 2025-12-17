import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/item.dart';
import '../models/user_model.dart';

class FeedItemCard extends StatelessWidget {
  final ItemModel item;
  final VoidCallback onTap;

  const FeedItemCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isLost = item.type == 'lost';
    final Color typeColor = isLost ? Colors.redAccent : Colors.green;
    final String typeText = isLost ? 'LOST' : 'FOUND';

    // Calculate time ago
    final DateTime date = item.postedAt?.toDate() ?? DateTime.now();
    final String timeString = timeago.format(date, locale: 'en_short');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. IMAGE AREA
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  child: AspectRatio(
                    aspectRatio: 4 / 3, // Standard photo shape
                    child: item.photos.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.photos.first,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[100]),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[100],
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey[400],
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.grey[100],
                            child: Icon(
                              isLost ? Icons.search : Icons.redeem,
                              size: 50,
                              color: Colors.grey[300],
                            ),
                          ),
                  ),
                ),

                // 2. STATUS BADGE (Floating)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: typeColor.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      typeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // 3. DETAILS AREA
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Price/Reward (if any)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeString,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Description Preview
                  Text(
                    item.desc,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),

                  // Location Row
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.blue[400],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.locationText.isNotEmpty
                              ? item.locationText
                              : 'Unknown Location',
                          style: TextStyle(
                            color: Colors.blue[400],
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
