// Every journey in one app build: `flutter drive` compiles once per target,
// which is most of a run's time. scripts/e2e.sh runs this by default; pass a
// single journey file to it to run just that one.
import 'journeys/auth_test.dart' as auth;

void main() {
  auth.main();
}
