import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../bloc/location/location_bloc.dart';
import '../shared/glass_container.dart';

class MapControls extends StatelessWidget {
  final MapController mapController;
  final VoidCallback onToggleTripPlanner;
  final bool showTripPlanner;
  final bool isBottomModalVisible;

  const MapControls({
    super.key,
    required this.mapController,
    required this.onToggleTripPlanner,
    this.showTripPlanner = false,
    required this.isBottomModalVisible,
  });

  void _zoomIn() {
    mapController.move(
      mapController.camera.center,
      mapController.camera.zoom + 1,
    );
  }

  void _zoomOut() {
    mapController.move(
      mapController.camera.center,
      mapController.camera.zoom - 1,
    );
  }

  void _pan(double latDelta, double lonDelta) {
    final currentCenter = mapController.camera.center;
    final newCenter = LatLng(
      currentCenter.latitude + latDelta,
      currentCenter.longitude + lonDelta,
    );
    mapController.move(newCenter, mapController.camera.zoom);
  }

  void _resetView(BuildContext context) {
    final locationState = context.read<LocationBloc>().state;
    if (locationState is LocationLoaded && locationState.position != null) {
      mapController.move(
        LatLng(
          locationState.position!.latitude,
          locationState.position!.longitude,
        ),
        13.0,
      );
    } else {
      mapController.move(const LatLng(37.7749, -122.4194), 13.0);
    }
  }

  Widget _buildGlassButton({
    required VoidCallback onPressed,
    required IconData icon,
    String? tooltip,
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: color ?? Colors.indigo),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        hoverColor: (color ?? Colors.indigo).withValues(alpha: 0.1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 600;
        return Stack(
          children: [
            // Trip Planner Toggle
            Positioned(
              top: 20,
              right: 20,
              child: GlassContainer(
                padding: const EdgeInsets.all(4),
                child: _buildGlassButton(
                  onPressed: onToggleTripPlanner,
                  icon: showTripPlanner ? Icons.map : Icons.route_outlined,
                  tooltip: showTripPlanner
                      ? 'Hide Trip Planner'
                      : 'Show Trip Planner',
                  color: showTripPlanner ? Colors.indigo : Colors.white70,
                ),
              ),
            ),
            // Pan Controls Group
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              bottom: isBottomModalVisible
                  ? (isDesktop ? 160 : 260)
                  : (isDesktop ? 20 : 120),
              right: 20,
              child: GlassContainer(
                padding: const EdgeInsets.all(4),
                borderRadius: 30, // Rounded for D-pad feel
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildGlassButton(
                      onPressed: () => _pan(0.01, 0),
                      icon: Icons.arrow_drop_up,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildGlassButton(
                          onPressed: () => _pan(0, -0.01),
                          icon: Icons.arrow_left,
                        ),
                        const SizedBox(width: 4),
                        _buildGlassButton(
                          onPressed: () => _resetView(context),
                          icon: Icons.my_location,
                          tooltip: 'My Location',
                        ),
                        const SizedBox(width: 4),
                        _buildGlassButton(
                          onPressed: () => _pan(0, 0.01),
                          icon: Icons.arrow_right,
                        ),
                      ],
                    ),
                    _buildGlassButton(
                      onPressed: () => _pan(-0.01, 0),
                      icon: Icons.arrow_drop_down,
                    ),
                  ],
                ),
              ),
            ),
            // Zoom Controls Group
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              bottom: isBottomModalVisible
                  ? (isDesktop ? 320 : 420)
                  : (isDesktop ? 180 : 280),
              right: 20,
              child: GlassContainer(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildGlassButton(
                      onPressed: _zoomIn,
                      icon: Icons.add,
                      tooltip: 'Zoom In',
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.search, color: Colors.indigo, size: 20),
                    const SizedBox(height: 4),
                    _buildGlassButton(
                      onPressed: _zoomOut,
                      icon: Icons.remove,
                      tooltip: 'Zoom Out',
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
