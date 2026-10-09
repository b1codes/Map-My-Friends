import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../models/trip.dart';
import '../../components/shared/glass_container.dart';
import '../../utils/app_theme.dart';
import '../../services/routing_service.dart';
import '../../bloc/map/map_settings_cubit.dart';
import '../../utils/window_size.dart';
import '../../components/shared/glass_surfaces.dart';

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
    // This route draws glass in four places — the back button, the header, and
    // one surface per stop and per leg in the timeline. Grouping them means the
    // engine samples the backdrop once for the whole screen instead of once per
    // row, which is what keeps a long itinerary inside the GPU budget.
    return BackdropGroup(child: _buildContent(context));
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context);
    final isWide = MapWindow(size.size).isWide;

    Widget buildLeadingButton() {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: GlassContainer(
          padding: EdgeInsets.zero,
          borderRadius: MapGlass.radiusMd,
          child: IconButton(
            icon: Icon(
              Icons.adaptive.arrow_back,
              color: theme.colorScheme.onSurface,
            ),
            tooltip: 'Back',
            onPressed: () => Navigator.pop(context),
          ),
        ),
      );
    }

    if (isWide) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: buildLeadingButton(),
        ),
        body: Row(
          children: [
            // Left Panel (Timeline & Info)
            SafeArea(
              right: false,
              child: Container(
                width: 380,
                padding: const EdgeInsets.only(top: 56), // below appbar
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    Expanded(child: _buildStopsList(context, isWide: true)),
                  ],
                ),
              ),
            ),
            // Right Panel (Map)
            Expanded(
              child: Stack(
                children: [
                  _buildMap(),
                  // Visual separation border on the left edge
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1,
                      color: MapGlass.inlayEdge(
                        theme.brightness,
                      ).withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: buildLeadingButton(),
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
                _buildStopsList(context, isWide: false),
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

        return BlocBuilder<MapSettingsCubit, MapSettingsState>(
          builder: (context, settingsState) {
            final isDark = settingsState.themeMode == ThemeMode.system
                ? Theme.of(context).brightness == Brightness.dark
                : settingsState.themeMode == ThemeMode.dark;

            String tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
            if (settingsState.mapType == MapType.satellite) {
              tileUrl =
                  'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
            } else if (settingsState.mapType == MapType.minimal) {
              tileUrl = isDark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                  : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
            } else if (isDark) {
              tileUrl =
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
            } else {
              final locale = Localizations.localeOf(context).languageCode;
              if (locale == 'de') {
                tileUrl =
                    'https://{s}.tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png';
              } else if (locale == 'fr') {
                tileUrl =
                    'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png';
              }
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
                  urlTemplate: tileUrl,
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.mapmyfriends.app',
                ),
                if (points.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.7),
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
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            String.fromCharCode(65 + idx),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
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
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

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
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: onSurface,
                    ),
                  ),
                ),
                _buildStatusBadge(context, widget.trip.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('MMMM d, yyyy').format(widget.trip.date),
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, TripStatus status) {
    final brightness = Theme.of(context).brightness;
    final Color color = switch (status) {
      TripStatus.booked => MapPalette.journeyConfirmed.ink(brightness),
      TripStatus.cancelled => MapPalette.journeyCancelled.ink(brightness),
      _ => MapPalette.journeyPlanned.ink(brightness),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(MapGlass.radiusMd),
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

  Widget _buildStopsList(BuildContext context, {required bool isWide}) {
    final List<dynamic> timelineItems = [];
    for (int i = 0; i < widget.trip.stops.length; i++) {
      timelineItems.add(widget.trip.stops[i]);
      // Find leg that starts at this stop
      final leg = widget.trip.legs
          .where((l) => l.departureStopId == widget.trip.stops[i].id)
          .firstOrNull;
      if (leg != null) {
        timelineItems.add(leg);
      } else if (i < widget.trip.stops.length - 1) {
        // Fallback for missing legs in draft
        timelineItems.add(
          TripLeg(
            departureStopId: widget.trip.stops[i].id ?? '',
            arrivalStopId: widget.trip.stops[i + 1].id ?? '',
          ),
        );
      }
    }

    final listView = ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: timelineItems.length,
      itemBuilder: (context, index) {
        final item = timelineItems[index];
        if (item is TripStop) {
          return _buildStopItem(context, item, widget.trip.stops.indexOf(item));
        } else if (item is TripLeg) {
          return _buildLegItem(context, item);
        }
        return const SizedBox.shrink();
      },
    );

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: listView,
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      padding: const EdgeInsets.only(bottom: 20),
      child: listView,
    );
  }

  Widget _buildLegItem(BuildContext context, TripLeg leg) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    IconData transportIcon;
    switch (leg.transportType) {
      case 'FLIGHT':
        transportIcon = Icons.flight_takeoff;
        break;
      case 'TRAIN':
        transportIcon = Icons.train;
        break;
      case 'BUS':
        transportIcon = Icons.directions_bus;
        break;
      default:
        transportIcon = Icons.directions_car;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Column(
            children: [
              Container(
                width: 2,
                height: 20,
                color: onSurface.withValues(alpha: 0.2),
              ),
              InkWell(
                onTap: () => _showLegDetails(context, leg),
                child: GlassContainer(
                  padding: const EdgeInsets.all(8),
                  borderRadius: 20, // pill: half the 40px timeline dot
                  child: Icon(
                    transportIcon,
                    color: onSurface.withValues(alpha: 0.7),
                    size: 20,
                  ),
                ),
              ),
              Container(
                width: 2,
                height: 20,
                color: onSurface.withValues(alpha: 0.2),
              ),
            ],
          ),
          const SizedBox(width: 16),
          if (leg.bookingReference.isNotEmpty)
            Text(
              'Ref: ${leg.bookingReference}',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  void _showLegDetails(BuildContext context, TripLeg leg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      isScrollControlled: true,
      builder: (context) => _LegDetailsSheet(leg: leg),
    );
  }

  Widget _buildStopItem(BuildContext context, TripStop stop, int index) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    String name = '';
    String address = stop.snapshotAddress ?? '';

    if (stop.snapshotMetadata != null) {
      final peopleData = stop.snapshotMetadata!['people'];
      if (peopleData != null) {
        if (peopleData is List) {
          name = peopleData
              .map((p) => p is Map ? p['name'] : p.toString())
              .join(', ');
        } else {
          name = peopleData.toString();
        }
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
        borderRadius: MapGlass.radiusMd,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(65 + index),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
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
                    style: TextStyle(
                      color: onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (address.isNotEmpty)
                    Text(
                      address,
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.7),
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

class _LegDetailsSheet extends StatelessWidget {
  final TripLeg leg;

  const _LegDetailsSheet({required this.leg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return GlassSheet(
      padding: const EdgeInsets.all(MapSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Leg Details',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: onSurface),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInfoRow(context, 'Transport Type', leg.transportType),
          _buildInfoRow(
            context,
            'Booking Ref',
            leg.bookingReference.isEmpty ? 'Not set' : leg.bookingReference,
          ),
          if (leg.departureTime != null)
            _buildInfoRow(
              context,
              'Departure',
              DateFormat('HH:mm, MMM d').format(leg.departureTime!),
            ),
          if (leg.arrivalTime != null)
            _buildInfoRow(
              context,
              'Arrival',
              DateFormat('HH:mm, MMM d').format(leg.arrivalTime!),
            ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // TODO: Implement editing
                Navigator.pop(context);
                GlassToast.show(
                  context,
                  'Editing will be implemented in the next iteration.',
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Details'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
          ),
          Text(
            value,
            style: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
