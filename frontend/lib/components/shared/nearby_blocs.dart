import '../../bloc/airport/airport_bloc.dart';
import '../../bloc/station/station_bloc.dart';

/// The blocs [NearbyAirportsSection] and [NearbyStationsSection] read instead
/// of creating their own.
///
/// The app never provides one: each section creates a bloc, loads it for its
/// coordinate, and closes it. A test or the Widgetbook catalog provides one
/// above a screen to pin every section under it to a state without the
/// network. The sections neither load nor close these; whoever provides them
/// owns them.
///
/// A holder rather than the blocs themselves, because the app already
/// provides an [AirportBloc] and a [StationBloc] for the map layers, and a
/// section must not pick those up.
class NearbyBlocs {
  const NearbyBlocs({required this.airports, required this.stations});

  final AirportBloc airports;
  final StationBloc stations;
}
