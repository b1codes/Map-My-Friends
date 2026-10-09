import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/auth/auth_bloc.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/map/local_map_settings_cubit.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/theme/theme_cubit.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';

import 'fake_blocs.dart';
import 'fixtures.dart';

/// Provides every bloc the app's widgets read, each pinned to a given state.
///
/// Every provider is always present, whatever the use case renders. A screen
/// that pushes another (People → Person details → Edit) reads blocs the first
/// screen never touched, and a missing provider would surface as a
/// ProviderNotFound crash in the middle of a click-through.
///
/// The blocs live as long as the scope. When a knob changes a state, the
/// existing bloc is moved to it rather than replaced, so the widget under
/// test sees a real state transition — its BlocListeners fire and its local
/// state (scroll position, form input) survives, the same as in the app.
class StoryScope extends StatefulWidget {
  const StoryScope({
    super.key,
    required this.child,
    this.auth = const Unauthenticated(),
    this.location,
    this.people,
    this.pulse,
    this.profile,
    this.airports = const MapAirportsLoaded([]),
    this.stations = const MapStationsLoaded([]),
    this.trip = const TripState(),
    this.mapSettings = const MapSettingsState(),
  });

  final Widget child;
  final AuthState auth;

  /// Defaults to the sample position in Manhattan.
  final LocationState? location;

  /// Defaults to the sample roster.
  final PeopleState? people;

  /// Defaults to the sample roster and its contact history.
  final PulseState? pulse;

  /// Defaults to the sample signed-in profile.
  final ProfileState? profile;

  final AirportState airports;
  final StationState stations;
  final TripState trip;
  final MapSettingsState mapSettings;

  @override
  State<StoryScope> createState() => _StoryScopeState();
}

class _StoryScopeState extends State<StoryScope> {
  late final StoryAuthBloc _auth = StoryAuthBloc(widget.auth);
  late final StoryLocationBloc _location = StoryLocationBloc(_locationState);
  late final StoryPeopleBloc _people = StoryPeopleBloc(_peopleState);
  late final StoryPulseBloc _pulse = StoryPulseBloc(_pulseState);
  late final StoryProfileBloc _profile = StoryProfileBloc(_profileState);
  late final StoryAirportBloc _airports = StoryAirportBloc(widget.airports);
  late final StoryStationBloc _stations = StoryStationBloc(widget.stations);
  late final StoryTripBloc _trip = StoryTripBloc(widget.trip);
  late final StoryMapSettingsCubit _mapSettings = StoryMapSettingsCubit(
    widget.mapSettings,
  );
  late final LocalMapSettingsCubit _localMapSettings = LocalMapSettingsCubit(
    initialState: widget.mapSettings,
  );
  final ThemeCubit _theme = ThemeCubit();

  LocationState get _locationState => widget.location ?? Fixtures.location;
  PeopleState get _peopleState =>
      widget.people ?? PeopleLoaded(Fixtures.people);
  PulseState get _pulseState => widget.pulse ?? Fixtures.pulseLoaded();
  ProfileState get _profileState => widget.profile ?? Fixtures.profile;

  @override
  void didUpdateWidget(StoryScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _auth.seed(widget.auth);
    _location.seed(_locationState);
    _people.seed(_peopleState);
    _pulse.seed(_pulseState);
    _profile.seed(_profileState);
    _airports.seed(widget.airports);
    _stations.seed(widget.stations);
    _trip.seed(widget.trip);
    _mapSettings.seed(widget.mapSettings);
  }

  @override
  void dispose() {
    for (final bloc in <BlocBase<Object?>>[
      _auth,
      _location,
      _people,
      _pulse,
      _profile,
      _airports,
      _stations,
      _trip,
      _mapSettings,
      _localMapSettings,
      _theme,
    ]) {
      bloc.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _auth),
        BlocProvider<LocationBloc>.value(value: _location),
        BlocProvider<PeopleBloc>.value(value: _people),
        BlocProvider<PulseBloc>.value(value: _pulse),
        BlocProvider<ProfileBloc>.value(value: _profile),
        BlocProvider<AirportBloc>.value(value: _airports),
        BlocProvider<StationBloc>.value(value: _stations),
        BlocProvider<TripBloc>.value(value: _trip),
        BlocProvider<MapSettingsCubit>.value(value: _mapSettings),
        BlocProvider<LocalMapSettingsCubit>.value(value: _localMapSettings),
        BlocProvider<ThemeCubit>.value(value: _theme),
      ],
      child: widget.child,
    );
  }
}
