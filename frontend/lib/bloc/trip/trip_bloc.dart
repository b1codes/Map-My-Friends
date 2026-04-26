import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import '../../models/trip.dart';
import '../../models/person.dart';
import '../../services/routing_service.dart';
import '../../services/api_service.dart';
import 'trip_event.dart';
import 'trip_state.dart';

class TripBloc extends Bloc<TripEvent, TripState> {
  final RoutingService _routingService;
  final ApiService _apiService;
  int _routingRequestId = 0;

  TripBloc({RoutingService? routingService, ApiService? apiService})
    : _routingService = routingService ?? RoutingService(),
      _apiService = apiService ?? ApiService(),
      super(const TripState()) {
    on<AddStop>(_onAddStop);
    on<AddAirportStop>(_onAddAirportStop);
    on<AddStationStop>(_onAddStationStop);
    on<LinkPersonToStop>(_onLinkPersonToStop);
    on<RemoveStop>(_onRemoveStop);
    on<ReorderStops>(_onReorderStops);
    on<ClearTrip>(_onClearTrip);
    on<OptimizeTrip>(_onOptimizeTrip);
    on<SaveTrip>(_onSaveTrip);
    on<FetchUserTrips>(_onFetchUserTrips);
    on<LoadTrip>(_onLoadTrip);
    on<DeleteTrip>(_onDeleteTrip);
  }

  Future<void> _onAddStop(AddStop event, Emitter<TripState> emit) async {
    if (event.person.latitude == null || event.person.longitude == null) return;

    // Auto-fill hub if available
    Airport? preferredAirport = event.person.preferredAirport;
    Station? preferredStation = event.person.preferredStation;

    LatLng location = LatLng(event.person.latitude!, event.person.longitude!);
    if (preferredAirport != null) {
      location = LatLng(preferredAirport.latitude, preferredAirport.longitude);
    } else if (preferredStation != null) {
      location = LatLng(preferredStation.latitude, preferredStation.longitude);
    }

    final newStop = TripStop(
      people: [event.person],
      airport: preferredAirport,
      station: preferredStation,
      location: location,
      sequenceOrder: state.stops.length,
    );

    await _handleAddStop(newStop, emit);
  }

  Future<void> _onAddAirportStop(
    AddAirportStop event,
    Emitter<TripState> emit,
  ) async {
    final newStop = TripStop(
      airport: event.airport,
      location: LatLng(event.airport.latitude, event.airport.longitude),
      sequenceOrder: state.stops.length,
    );

    await _handleAddStop(newStop, emit);
  }

  Future<void> _onAddStationStop(
    AddStationStop event,
    Emitter<TripState> emit,
  ) async {
    final newStop = TripStop(
      station: event.station,
      location: LatLng(event.station.latitude, event.station.longitude),
      sequenceOrder: state.stops.length,
    );

    await _handleAddStop(newStop, emit);
  }

  void _onLinkPersonToStop(LinkPersonToStop event, Emitter<TripState> emit) {
    if (event.stopIndex < 0 || event.stopIndex >= state.stops.length) return;

    final stop = state.stops[event.stopIndex];
    if (stop.people.any((p) => p.id == event.person.id)) return;

    final newPeople = List<Person>.from(stop.people)..add(event.person);

    // Auto-fill hub if stop has none
    Airport? newAirport = stop.airport;
    Station? newStation = stop.station;
    LatLng newLocation = stop.location;

    if (newAirport == null && newStation == null) {
      if (event.person.preferredAirport != null) {
        newAirport = event.person.preferredAirport;
        newLocation = LatLng(newAirport!.latitude, newAirport.longitude);
      } else if (event.person.preferredStation != null) {
        newStation = event.person.preferredStation;
        newLocation = LatLng(newStation!.latitude, newStation.longitude);
      }
    }

    final updatedStop = stop.copyWith(
      people: newPeople,
      airport: newAirport,
      station: newStation,
      location: newLocation,
    );

    final newStops = List<TripStop>.from(state.stops);
    newStops[event.stopIndex] = updatedStop;

    emit(state.copyWith(stops: newStops));
  }

  Future<void> _handleAddStop(TripStop stop, Emitter<TripState> emit) async {
    final newStops = List<TripStop>.from(state.stops)..add(stop);
    emit(state.copyWith(stops: newStops, isOptimizing: true));

    final requestId = ++_routingRequestId;
    final route = await _routingService.getRoute(newStops);
    if (requestId != _routingRequestId) return;

    emit(state.copyWith(routePoints: route, isOptimizing: false));
  }

  Future<void> _onRemoveStop(RemoveStop event, Emitter<TripState> emit) async {
    final newStops = List<TripStop>.from(state.stops)..removeAt(event.index);
    final sortedStops = _resortStops(newStops);
    emit(state.copyWith(stops: sortedStops, isOptimizing: true));

    final requestId = ++_routingRequestId;
    final route = await _routingService.getRoute(sortedStops);
    if (requestId != _routingRequestId) return;

    emit(state.copyWith(routePoints: route, isOptimizing: false));
  }

  Future<void> _onReorderStops(
    ReorderStops event,
    Emitter<TripState> emit,
  ) async {
    var newStops = List<TripStop>.from(state.stops);
    int newIndex = event.newIndex;
    if (event.oldIndex < newIndex) newIndex -= 1;
    final item = newStops.removeAt(event.oldIndex);
    newStops.insert(newIndex, item);

    final sortedStops = _resortStops(newStops);
    emit(state.copyWith(stops: sortedStops, isOptimizing: true));

    final requestId = ++_routingRequestId;
    final route = await _routingService.getRoute(sortedStops);
    if (requestId != _routingRequestId) return;

    emit(state.copyWith(routePoints: route, isOptimizing: false));
  }

  void _onClearTrip(ClearTrip event, Emitter<TripState> emit) {
    _routingRequestId++; // Cancel any pending requests
    emit(state.copyWith(
      stops: [],
      routePoints: [],
      isOptimizing: false,
      clearCurrentTripId: true,
    ));
  }

  Future<void> _onOptimizeTrip(
    OptimizeTrip event,
    Emitter<TripState> emit,
  ) async {
    if (state.stops.length < 3) return;
    emit(state.copyWith(isOptimizing: true));

    final requestId = ++_routingRequestId;
    final optimized = _solveTSP(state.stops);
    final route = await _routingService.getRoute(optimized);
    if (requestId != _routingRequestId) return;

    emit(
      state.copyWith(
        stops: _resortStops(optimized),
        routePoints: route,
        isOptimizing: false,
      ),
    );
  }

  Future<void> _onSaveTrip(SaveTrip event, Emitter<TripState> emit) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final tripToSave = Trip(
        id: state.currentTripId,
        name: event.name,
        date: event.date,
        status: event.status,
        stops: state.stops,
      );

      Trip savedTrip;
      if (tripToSave.id != null) {
        savedTrip = await _apiService.updateTrip(tripToSave);
      } else {
        savedTrip = await _apiService.createTrip(tripToSave);
      }

      emit(state.copyWith(
        isLoading: false,
        currentTripId: savedTrip.id,
      ));
      add(const FetchUserTrips());
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onFetchUserTrips(
    FetchUserTrips event,
    Emitter<TripState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final trips = await _apiService.getTrips();
      emit(state.copyWith(isLoading: false, userTrips: trips));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadTrip(LoadTrip event, Emitter<TripState> emit) async {
    emit(state.copyWith(
      isLoading: true,
      stops: event.trip.stops,
      currentTripId: event.trip.id,
      clearError: true,
    ));

    final requestId = ++_routingRequestId;
    final route = await _routingService.getRoute(event.trip.stops);
    if (requestId != _routingRequestId) return;

    emit(state.copyWith(routePoints: route, isLoading: false));
  }

  Future<void> _onDeleteTrip(DeleteTrip event, Emitter<TripState> emit) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      await _apiService.deleteTrip(event.tripId);
      if (state.currentTripId == event.tripId) {
        add(const ClearTrip());
      }
      add(const FetchUserTrips());
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  List<TripStop> _resortStops(List<TripStop> stops) {
    return List.generate(
      stops.length,
      (i) => stops[i].copyWith(sequenceOrder: i),
    );
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
        final d = distance.as(
          LengthUnit.Meter,
          path.last.location,
          unvisited[i].location,
        );
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
      total += distance.as(
        LengthUnit.Meter,
        path[i].location,
        path[i + 1].location,
      );
    }
    return total;
  }
}
