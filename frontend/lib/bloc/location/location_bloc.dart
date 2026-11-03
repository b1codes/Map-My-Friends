import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';

part 'location_event.dart';
part 'location_state.dart';

class LocationBloc extends Bloc<LocationEvent, LocationState> {
  LocationBloc() : super(LocationInitial()) {
    on<LoadLocation>(_onLoadLocation);
    on<RequestPermission>(_onRequestPermission);
    on<UpdateUserAddress>(_onUpdateUserAddress);
  }

  Future<void> _onLoadLocation(
    LoadLocation event,
    Emitter<LocationState> emit,
  ) async {
    emit(LocationLoading());
    try {
      bool serviceEnabled;
      LocationPermission permission;

      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        emit(const LocationError('Location services are disabled.'));
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          emit(LocationPermissionDenied());
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        emit(LocationPermissionDeniedForever());
        return;
      }

      // When we reach here, permissions are granted and we can
      // continue accessing the position of the device.
      final Position position = await Geolocator.getCurrentPosition();
      emit(LocationLoaded(position: position));
    } catch (e) {
      emit(LocationError(e.toString()));
    }
  }

  Future<void> _onRequestPermission(
    RequestPermission event,
    Emitter<LocationState> emit,
  ) async {
    // Logic handled in LoadLocation, but can be explicit here if needed
    add(LoadLocation());
  }

  Future<void> _onUpdateUserAddress(
    UpdateUserAddress event,
    Emitter<LocationState> emit,
  ) async {
    // In a real app, you might geocode the address to get coordinates
    // For now, we just acknowledge the address update or save it to a repository
    // We can emit a state that reflects the address is saved
  }
}
