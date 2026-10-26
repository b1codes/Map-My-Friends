// Every journey in one app build: `flutter drive` compiles once per target,
// which is most of a run's time. scripts/e2e.sh runs this by default; pass a
// single journey file to it to run just that one.
import 'journeys/auth_test.dart' as auth;
import 'journeys/map_test.dart' as map;
import 'journeys/people_test.dart' as people;
import 'journeys/profile_test.dart' as profile;
import 'journeys/trips_test.dart' as trips;

void main() {
  auth.main();
  map.main();
  people.main();
  profile.main();
  trips.main();
}
