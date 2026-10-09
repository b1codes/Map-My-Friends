import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A live map to set map chrome against.
///
/// Map controls drive a real [MapController], so they need a [FlutterMap] to
/// attach to — tapping zoom on a detached controller throws. It also gives the
/// chrome the surface it is designed to float over: refraction is tuned for
/// tiles, not for the Ambient Field.
class MapBackdrop extends StatefulWidget {
  const MapBackdrop({
    super.key,
    required this.builder,
    this.center = const LatLng(40.7128, -74.0060),
    this.zoom = 11,
  });

  /// Builds the chrome laid over the map, given the map's controller.
  final Widget Function(BuildContext context, MapController controller) builder;

  final LatLng center;
  final double zoom;

  @override
  State<MapBackdrop> createState() => _MapBackdropState();
}

class _MapBackdropState extends State<MapBackdrop> {
  final MapController _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return BackdropGroup(
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: widget.center,
                initialZoom: widget.zoom,
              ),
              children: [
                TileLayer(
                  // The app's "standard" style in each appearance.
                  urlTemplate: dark
                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.mapmyfriends.widgetbook',
                  // See MapScreen: on web, aborting obsolete tile requests
                  // escapes as an uncaught DOMException on every zoom-out.
                  tileProvider: NetworkTileProvider(
                    abortObsoleteRequests: !kIsWeb,
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: widget.builder(context, _controller),
            ),
          ),
        ],
      ),
    );
  }
}
