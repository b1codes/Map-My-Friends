import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/airport_service.dart';
import 'airport_event.dart';
import 'airport_state.dart';

class AirportBloc extends Bloc<AirportEvent, AirportState> {
  final AirportService _airportService = AirportService();

  AirportBloc() : super(AirportInitial()) {
    on<LoadMapAirports>(_onLoadMapAirports);
    on<LoadNearestAirports>(_onLoadNearestAirports);
  }

  Future<void> _onLoadMapAirports(
    LoadMapAirports event,
    Emitter<AirportState> emit,
  ) async {
    emit(AirportLoading());
    try {
      final airports = await _airportService.loadAirportsFromAsset();
      emit(MapAirportsLoaded(airports));
    } catch (e) {
      emit(AirportError(e.toString()));
    }
  }

  Future<void> _onLoadNearestAirports(
    LoadNearestAirports event,
    Emitter<AirportState> emit,
  ) async {
    emit(AirportLoading());
    try {
      final airports = await _airportService.getNearestAirports(
        event.latitude,
        event.longitude,
        count: event.count,
      );
      emit(NearestAirportsLoaded(airports));
    } catch (e) {
      emit(AirportError(e.toString()));
    }
  }
}
