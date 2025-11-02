import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/item.dart';
import '../services/item_service.dart';
import 'item_detail_page.dart';

class MapViewPage extends StatelessWidget {
  const MapViewPage({super.key});

  //This is the starting camera position
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(2.8443, 101.7818), //Defaults to USIM coordinates
    zoom: 12,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map Search')),
      body: StreamBuilder<List<ItemModel>>(
        // 1. Listen to your new stream
        stream: ItemService.instance.allActiveItems(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final items = snapshot.data ?? [];

          // 2. Convert the list of items into a Set of Markers
          final markers = _buildMarkers(context, items);

          return GoogleMap(
            initialCameraPosition: _initialPosition,
            markers: markers,
            mapType: MapType.normal,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          );
        },
      ),
    );
  }

  /// Helper method to build the set of markers from the item list
  Set<Marker> _buildMarkers(BuildContext context, List<ItemModel> items) {
    return items
        .map(
          (item) => Marker(
            markerId: MarkerId(item.id),
            position: LatLng(item.lat, item.lng),
            infoWindow: InfoWindow(
              title: item.title,
              snippet: 'Type: ${item.type} | Category: ${item.category}',
              // 3. Define what happens when the info window (popup) is tapped
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ItemDetailPage(item: item)),
                );
              },
            ),
            // Use different pin color for 'lost' and 'found' items
            icon: item.type == 'lost'
                ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)
                : BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
          ),
        )
        .toSet();
  }
}
