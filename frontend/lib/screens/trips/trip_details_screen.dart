import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../models/trip.dart';
import '../../components/shared/glass_container.dart';
import '../../services/routing_service.dart';

class TripDetailsScreen extends StatefulWidget {
  final Trip trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  late Future<List<LatLng>> _routeFuture;
  final RoutingService _routingService = RoutingService();

  @override
  void initState() {
    super.initState();
    _routeFuture = _routingService.getRoute(widget.trip.stops);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GlassContainer(
            padding: EdgeInsets.zero,
            borderRadius: 12,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Non-interactive Map Background
          _buildMap(),

          // Content Overlay
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildHeader(context),
                const Spacer(),
                _buildStopsList(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FutureBuilder<List<LatLng>>(
      future: _routeFuture,
      builder: (context, snapshot) {
        final List<LatLng> points = snapshot.data ?? [];

        // Calculate bounds to center the map
        LatLngBounds? bounds;
        if (widget.trip.stops.length > 1) {
          bounds = LatLngBounds.fromPoints(
            widget.trip.stops.map((s) => s.location).toList(),
          );
        }

        return FlutterMap(
          options: MapOptions(
            initialCameraFit: bounds != null
                ? CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(100),
                  )
                : null,
            initialCenter: widget.trip.stops.isNotEmpty
                ? widget.trip.stops.first.location
                : const LatLng(0, 0),
            initialZoom: 10,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.app',
            ),
            if (points.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    color: Colors.indigo.withValues(alpha: 0.7),
                    strokeWidth: 5,
                  ),
                ],
              ),
            MarkerLayer(
              markers: widget.trip.stops.asMap().entries.map((entry) {
                final idx = entry.key;
                final stop = entry.value;
                return Marker(
                  point: stop.location,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.indigo,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        String.fromCharCode(65 + idx),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: GlassContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.trip.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                _buildStatusBadge(widget.trip.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('MMMM d, yyyy').format(widget.trip.date),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(TripStatus status) {
    Color color;
    switch (status) {
      case TripStatus.booked:
        color = Colors.greenAccent;
        break;
      case TripStatus.cancelled:
        color = Colors.redAccent;
        break;
      default:
        color = Colors.orangeAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStopsList(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4,
      padding: const EdgeInsets.only(bottom: 20),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: widget.trip.stops.length,
        itemBuilder: (context, index) {
          final stop = widget.trip.stops[index];
          return _buildStopItem(context, stop, index);
        },
      ),
    );
  }

  Widget _buildStopItem(BuildContext context, TripStop stop, int index) {
    String name = '';
    String address = stop.snapshotAddress ?? '';

    if (stop.snapshotMetadata != null) {
      if (stop.snapshotMetadata!['people'] != null) {
        name = stop.snapshotMetadata!['people'];
      } else if (stop.snapshotMetadata!['hub'] != null) {
        name = stop.snapshotMetadata!['hub']['name'];
      }
    }

    if (name.isEmpty) {
      if (stop.people.isNotEmpty) {
        name = stop.people
            .map((p) => '${p.firstName} ${p.lastName}')
            .join(', ');
      } else if (stop.airport != null) {
        name = stop.airport!.name;
      } else if (stop.station != null) {
        name = stop.station!.name;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 12,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.indigo,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(65 + index),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (address.isNotEmpty)
                    Text(
                      address,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
