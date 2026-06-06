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

  // Fallback camera (USIM) when we can't get the device location, so the
  // picker still opens instead of spinning forever (L8).
  static const _fallback = LatLng(2.8443, 101.7818);

  Future<LatLng> _currentLatLng() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      // Denied / deniedForever / services off: just use the fallback camera;
      // the user can still tap to pick a point.
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return _fallback;
      }
      final pos = await Geolocator.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return _fallback;
    }
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
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // _currentLatLng never throws now, but guard anyway so a future change
        // can't reintroduce the infinite spinner.
        final start = snap.data ?? _fallback;
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
