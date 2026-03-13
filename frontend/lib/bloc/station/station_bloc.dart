import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/station_service.dart';
import 'station_event.dart';
import 'station_state.dart';

class StationBloc extends Bloc<StationEvent, StationState> {
  final StationService _stationService = StationService();

  StationBloc() : super(StationInitial()) {
    on<LoadMapStations>(_onLoadMapStations);
    on<FetchNearestStations>(_onFetchNearestStations);
  }

  Future<void> _onLoadMapStations(
    LoadMapStations event,
    Emitter<StationState> emit,
  ) async {
    emit(StationLoading());
    try {
      final stations = await _stationService.loadStationsFromAsset();
      emit(MapStationsLoaded(stations));
    } catch (e) {
      emit(StationError(e.toString()));
    }
  }

  Future<void> _onFetchNearestStations(
    FetchNearestStations event,
    Emitter<StationState> emit,
  ) async {
    emit(StationLoading());
    try {
      final stations = await _stationService.getNearestStations(
        event.latitude,
        event.longitude,
        count: event.count,
      );
      emit(NearestStationsLoaded(stations));
    } catch (e) {
      emit(StationError(e.toString()));
    }
  }
}
