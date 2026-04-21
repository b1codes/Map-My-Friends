import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import '../../models/trip.dart';
import '../../services/routing_service.dart';
import 'trip_event.dart';
import 'trip_state.dart';

class TripBloc extends Bloc<TripEvent, TripState> {
  final RoutingService _routingService = RoutingService();

  TripBloc() : super(const TripState()) {
    on<AddStop>(_onAddStop);
    on<RemoveStop>(_onRemoveStop);
    on<ReorderStops>(_onReorderStops);
    on<ClearTrip>(_onClearTrip);
    on<OptimizeTrip>(_onOptimizeTrip);
  }

  Future<void> _onAddStop(AddStop event, Emitter<TripState> emit) async {
    if (event.person.latitude == null || event.person.longitude == null) return;
    
    final newStop = TripStop(
      id: DateTime.now().toString(),
      person: event.person,
      location: LatLng(event.person.latitude!, event.person.longitude!),
      sequenceOrder: state.stops.length,
    );
    
    final newStops = List<TripStop>.from(state.stops)..add(newStop);
    emit(state.copyWith(stops: newStops, isLoading: true));
    
    final route = await _routingService.getRoute(newStops);
    emit(state.copyWith(routePoints: route, isLoading: false));
  }

  Future<void> _onRemoveStop(RemoveStop event, Emitter<TripState> emit) async {
    final newStops = List<TripStop>.from(state.stops)..removeAt(event.index);
    emit(state.copyWith(stops: _resortStops(newStops), isLoading: true));
    
    final route = await _routingService.getRoute(newStops);
    emit(state.copyWith(routePoints: route, isLoading: false));
  }

  Future<void> _onReorderStops(ReorderStops event, Emitter<TripState> emit) async {
    var newStops = List<TripStop>.from(state.stops);
    int newIndex = event.newIndex;
    if (event.oldIndex < newIndex) newIndex -= 1;
    final item = newStops.removeAt(event.oldIndex);
    newStops.insert(newIndex, item);
    
    emit(state.copyWith(stops: _resortStops(newStops), isLoading: true));
    final route = await _routingService.getRoute(newStops);
    emit(state.copyWith(routePoints: route, isLoading: false));
  }

  void _onClearTrip(ClearTrip event, Emitter<TripState> emit) {
    emit(const TripState());
  }

  Future<void> _onOptimizeTrip(OptimizeTrip event, Emitter<TripState> emit) async {
    if (state.stops.length < 3) return;
    emit(state.copyWith(isLoading: true));
    
    final optimized = _solveTSP(state.stops);
    final route = await _routingService.getRoute(optimized);
    
    emit(state.copyWith(stops: _resortStops(optimized), routePoints: route, isLoading: false));
  }

  List<TripStop> _resortStops(List<TripStop> stops) {
    return List.generate(stops.length, (i) => stops[i].copyWith(sequenceOrder: i));
  }

  List<TripStop> _solveTSP(List<TripStop> stops) {
    List<TripStop>? bestPath;
    double minDistance = double.infinity;

    for (int start = 0; start < stops.length; start++) {
      final currentPath = _greedyPath(stops, start);
      final totalDist = _calculateTotalDistance(currentPath);
      if (totalDist < minDistance) {
        minDistance = totalDist;
        bestPath = currentPath;
      }
    }
    return bestPath ?? stops;
  }

  List<TripStop> _greedyPath(List<TripStop> stops, int startIndex) {
    final unvisited = List<TripStop>.from(stops);
    final path = <TripStop>[unvisited.removeAt(startIndex)];
    final distance = const Distance();

    while (unvisited.isNotEmpty) {
      int nearestIdx = 0;
      double minDist = double.infinity;
      for (int i = 0; i < unvisited.length; i++) {
        final d = distance.as(LengthUnit.Meter, path.last.location, unvisited[i].location);
        if (d < minDist) {
          minDist = d;
          nearestIdx = i;
        }
      }
      path.add(unvisited.removeAt(nearestIdx));
    }
    return path;
  }

  double _calculateTotalDistance(List<TripStop> path) {
    final distance = const Distance();
    double total = 0;
    for (int i = 0; i < path.length - 1; i++) {
      total += distance.as(LengthUnit.Meter, path[i].location, path[i + 1].location);
    }
    return total;
  }
}
