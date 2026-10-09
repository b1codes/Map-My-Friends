import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_event.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/auth/auth_bloc.dart';
import 'package:map_my_friends/bloc/auth/auth_event.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/map/local_map_settings_cubit.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_event.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A bloc that holds whatever state the catalog gives it and never leaves it.
///
/// The app's blocs talk to Auth0, the Django API, OSRM, and the device's
/// location services the moment an event arrives. A catalog entry has to
/// render the same frame every time it is opened, offline, on any machine, so
/// every bloc a screen reads is replaced with one of these: same type, so
/// `context.read<PeopleBloc>()` resolves, but events are swallowed and the
/// state only changes when a knob says so.
///
/// Events are accepted rather than rejected because screens dispatch on
/// `initState` (Pulse loads, Me loads its profile); a bloc with no handler
/// throws on `add`, which would make every such screen uncatalogable.
///
/// [state] and [stream] are overridden rather than driven through `emit`,
/// which Bloc reserves for event handlers. It is the same seam
/// `bloc_test`'s `whenListen` uses, so widgets observe it identically.
abstract class InertBloc<E, S> extends Bloc<E, S> {
  InertBloc(super.initialState) : _current = initialState {
    on<E>((event, emit) {});
  }

  final StreamController<S> _changes = StreamController<S>.broadcast();
  S _current;

  @override
  S get state => _current;

  @override
  Stream<S> get stream => _changes.stream;

  /// Moves the bloc to [next], as if a real handler had emitted it.
  void seed(S next) {
    if (next == _current) return;
    _current = next;
    _changes.add(next);
  }

  @override
  Future<void> close() async {
    await _changes.close();
    return super.close();
  }
}

class StoryAuthBloc extends InertBloc<AuthEvent, AuthState>
    implements AuthBloc {
  StoryAuthBloc(super.initialState);
}

class StoryLocationBloc extends InertBloc<LocationEvent, LocationState>
    implements LocationBloc {
  StoryLocationBloc(super.initialState);
}

class StoryPeopleBloc extends InertBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {
  StoryPeopleBloc(super.initialState);
}

class StoryPulseBloc extends InertBloc<PulseEvent, PulseState>
    implements PulseBloc {
  StoryPulseBloc(super.initialState);
}

class StoryProfileBloc extends InertBloc<ProfileEvent, ProfileState>
    implements ProfileBloc {
  StoryProfileBloc(super.initialState);
}

class StoryAirportBloc extends InertBloc<AirportEvent, AirportState>
    implements AirportBloc {
  StoryAirportBloc(super.initialState);
}

class StoryStationBloc extends InertBloc<StationEvent, StationState>
    implements StationBloc {
  StoryStationBloc(super.initialState);
}

class StoryTripBloc extends InertBloc<TripEvent, TripState>
    implements TripBloc {
  StoryTripBloc(super.initialState);
}

/// Map settings, held in memory instead of SharedPreferences.
///
/// Unlike the blocs above this one stays live: its methods are pure state
/// changes with the same signatures as [LocalMapSettingsCubit], so toggling a
/// setting inside the catalog works exactly as it does in the app — it just
/// never writes to disk, and never reads the developer's own saved settings.
///
/// It also stands in for the map session's [LocalMapSettingsCubit], which
/// has no way to be moved to a new state from outside.
class StoryMapSettingsCubit extends LocalMapSettingsCubit
    implements MapSettingsCubit {
  StoryMapSettingsCubit(MapSettingsState initialState)
    : super(initialState: initialState);

  @override
  SharedPreferences get prefs => throw UnsupportedError(
    'The catalog keeps map settings in memory; nothing reads preferences.',
  );

  void seed(MapSettingsState next) {
    if (next != state) emit(next);
  }
}
