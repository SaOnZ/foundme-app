import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;

class MapPickerPage extends StatefulWidget {
  const MapPickerPage({super.key});

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  final _controller = Completer<GoogleMapController>();
  LatLng? _picked;
  String _label = 'Tap map to pick location';

  Future<LatLng> _currentLatLng() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      // ignore: curly_braces_in_flow_control_structures
      perm = await Geolocator.requestPermission();
    final pos = await Geolocator.getCurrentPosition();
    return LatLng(pos.latitude, pos.longitude);
  }

  Future<void> _onTap(LatLng p) async {
    setState(() {
      _picked = p;
      _label = 'Resolving address...';
    });
    try {
      final placemarks = await geo.placemarkFromCoordinates(
        p.latitude,
        p.longitude,
      );
      final pm = placemarks.first;
      setState(() {
        _label = '${pm.street}, ${pm.locality}, ${pm.administrativeArea}';
      });
    } catch (_) {
      setState(() {
        _label =
            '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _currentLatLng(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final start = snap.data as LatLng;
        return Scaffold(
          appBar: AppBar(title: const Text('Pick location')),
          body: GoogleMap(
            initialCameraPosition: CameraPosition(target: start, zoom: 16),
            onMapCreated: (c) => _controller.complete(c),
            myLocationEnabled: true,
            onTap: _onTap,
            markers: _picked == null
                ? {}
                : {Marker(markerId: const MarkerId('p'), position: _picked!)},
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(child: Text(_label, maxLines: 2)),
                  ElevatedButton(
                    onPressed: _picked == null
                        ? null
                        : () {
                            Navigator.pop(context, {
                              'lat': _picked!.latitude,
                              'lng': _picked!.longitude,
                              'text': _label,
                            });
                          },
                    child: const Text('Use'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
