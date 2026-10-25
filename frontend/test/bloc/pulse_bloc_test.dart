import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

Person _person(
  String id, {
  DateTime? lastContactedAt,
  String? lastContactChannel,
  int? cadence,
}) => Person(
  id: id,
  firstName: 'P$id',
  lastName: 'L',
  relationshipTag: 'FRIEND',
  city: 'C',
  state: 'S',
  country: 'X',
  lastContactedAt: lastContactedAt,
  lastContactChannel: lastContactChannel,
  contactCadenceDays: cadence,
);

ContactLog _log(String id, String personId, DateTime at) => ContactLog(
  id: id,
  personId: personId,
  channel: ContactChannel.message,
  contactedAt: at,
);

void main() {
  late MockApiService api;

  final jan1 = DateTime(2026, 1, 1);
  final jan5 = DateTime(2026, 1, 5);
  final jan10 = DateTime(2026, 1, 10);

  setUpAll(() {
    registerFallbackValue(_log('f', 'f', DateTime(2000)));
    registerFallbackValue(_person('fallback'));
  });

  setUp(() {
    api = MockApiService();
  });

  PulseBloc build() => PulseBloc(apiService: api);

  test('initial state is PulseInitial', () {
    final bloc = build();
    expect(bloc.state, PulseInitial());
    bloc.close();
  });

  group('LoadPulse', () {
    blocTest<PulseBloc, PulseState>(
      'loads people and logs, with logs sorted newest first',
      build: () {
        when(() => api.getPeople()).thenAnswer((_) async => [_person('1')]);
        when(() => api.getContactLogs()).thenAnswer(
          (_) async => [
            _log('a', '1', jan1),
            _log('c', '1', jan10),
            _log('b', '1', jan5),
          ],
        );
        return build();
      },
      act: (bloc) => bloc.add(LoadPulse()),
      expect: () => [
        PulseLoading(),
        isA<PulseLoaded>()
            .having((s) => s.people.map((p) => p.id), 'people', ['1'])
            .having((s) => s.logs.map((l) => l.id), 'logs', ['c', 'b', 'a'])
            .having((s) => s.actionError, 'actionError', isNull)
            .having((s) => s.actionNonce, 'actionNonce', 0),
      ],
    );

    blocTest<PulseBloc, PulseState>(
      'emits PulseError when either request fails',
      build: () {
        when(() => api.getPeople()).thenAnswer((_) async => []);
        when(
          () => api.getContactLogs(),
        ).thenThrow(Exception('Failed to load contact logs'));
        return build();
      },
      act: (bloc) => bloc.add(LoadPulse()),
      expect: () => [
        PulseLoading(),
        const PulseError('Exception: Failed to load contact logs'),
      ],
    );
  });

  group('LogContact', () {
    final ana = _person('1', lastContactedAt: jan1, lastContactChannel: 'CALL');
    final ben = _person('2');
    final oldLog = _log('old', '1', jan1);

    PulseLoaded seed({int nonce = 0}) =>
        PulseLoaded(people: [ana, ben], logs: [oldLog], actionNonce: nonce);

    blocTest<PulseBloc, PulseState>(
      'inserts a temp log and bumps recency, then swaps in the saved log',
      build: () {
        when(() => api.addContactLog(any())).thenAnswer((inv) async {
          final sent = inv.positionalArguments.first as ContactLog;
          return ContactLog(
            id: 'srv-1',
            personId: sent.personId,
            channel: sent.channel,
            contactedAt: sent.contactedAt,
            note: sent.note,
          );
        });
        return build();
      },
      seed: seed,
      act: (bloc) => bloc.add(
        LogContact(
          personId: '1',
          channel: ContactChannel.video,
          contactedAt: jan10,
          note: 'Catch-up',
        ),
      ),
      expect: () => [
        isA<PulseLoaded>()
            .having((s) => s.logs.first.id, 'first log id', startsWith('temp-'))
            .having((s) => s.logs.length, 'log count', 2)
            .having((s) => s.logs.last.id, 'older log', 'old')
            .having(
              (s) => s.people.first.lastContactedAt,
              'ana lastContactedAt',
              jan10,
            )
            .having(
              (s) => s.people.first.lastContactChannel,
              'ana channel',
              'VIDEO',
            )
            .having((s) => s.people[1], 'ben untouched', same(ben)),
        isA<PulseLoaded>()
            .having((s) => s.logs.map((l) => l.id), 'logs', ['srv-1', 'old'])
            .having(
              (s) => s.people.first.lastContactedAt,
              'ana lastContactedAt',
              jan10,
            )
            .having((s) => s.actionError, 'actionError', isNull),
      ],
      verify: (_) {
        final sent =
            verify(() => api.addContactLog(captureAny())).captured.single
                as ContactLog;
        expect(sent.personId, '1');
        expect(sent.channel, ContactChannel.video);
        expect(sent.contactedAt, jan10);
        expect(sent.note, 'Catch-up');
      },
    );

    blocTest<PulseBloc, PulseState>(
      'does not move recency backwards for a back-dated log',
      build: () {
        when(
          () => api.addContactLog(any()),
        ).thenAnswer((_) async => _log('srv-2', '1', jan1));
        return build();
      },
      seed: () => PulseLoaded(
        people: [
          _person('1', lastContactedAt: jan10, lastContactChannel: 'CALL'),
        ],
        logs: [_log('recent', '1', jan10)],
      ),
      act: (bloc) => bloc.add(
        LogContact(
          personId: '1',
          channel: ContactChannel.message,
          contactedAt: jan1,
        ),
      ),
      expect: () => [
        isA<PulseLoaded>()
            .having(
              (s) => s.people.single.lastContactedAt,
              'lastContactedAt',
              jan10,
            )
            .having(
              (s) => s.people.single.lastContactChannel,
              'channel',
              'CALL',
            )
            // Sorted newest first, so the back-dated log lands last.
            .having((s) => s.logs.first.id, 'first', 'recent'),
        isA<PulseLoaded>().having((s) => s.logs.map((l) => l.id), 'logs', [
          'recent',
          'srv-2',
        ]),
      ],
    );

    blocTest<PulseBloc, PulseState>(
      'rolls back and raises a one-shot error with a bumped nonce on failure',
      build: () {
        when(
          () => api.addContactLog(any()),
        ).thenThrow(Exception('Failed to log contact'));
        return build();
      },
      seed: () => seed(nonce: 3),
      act: (bloc) => bloc.add(
        LogContact(
          personId: '1',
          channel: ContactChannel.call,
          contactedAt: jan10,
        ),
      ),
      expect: () => [
        isA<PulseLoaded>().having((s) => s.logs.length, 'optimistic', 2),
        PulseLoaded(
          people: [ana, ben],
          logs: [oldLog],
          actionError: 'Could not save contact. Please try again.',
          actionNonce: 4,
        ),
      ],
    );

    blocTest<PulseBloc, PulseState>(
      'clears a previous actionError on the next successful emit',
      build: () {
        when(
          () => api.addContactLog(any()),
        ).thenAnswer((_) async => _log('srv-3', '2', jan5));
        return build();
      },
      seed: () => PulseLoaded(
        people: [ana, ben],
        logs: const [],
        actionError: 'old failure',
        actionNonce: 1,
      ),
      act: (bloc) => bloc.add(
        LogContact(
          personId: '2',
          channel: ContactChannel.message,
          contactedAt: jan5,
        ),
      ),
      expect: () => [
        isA<PulseLoaded>()
            .having((s) => s.actionError, 'actionError', isNull)
            .having((s) => s.actionNonce, 'actionNonce', 1)
            .having((s) => s.people[1].lastContactedAt, 'ben recency', jan5),
        isA<PulseLoaded>().having((s) => s.logs.map((l) => l.id), 'logs', [
          'srv-3',
        ]),
      ],
    );

    blocTest<PulseBloc, PulseState>(
      'is ignored until the roster has loaded',
      build: build,
      act: (bloc) => bloc.add(
        LogContact(
          personId: '1',
          channel: ContactChannel.call,
          contactedAt: jan10,
        ),
      ),
      expect: () => <PulseState>[],
      verify: (_) => verifyNever(() => api.addContactLog(any())),
    );
  });

  group('SetCadence', () {
    final ana = _person('1', cadence: 30);
    final ben = _person('2');

    blocTest<PulseBloc, PulseState>(
      'applies the cadence optimistically, then keeps the saved person',
      build: () {
        when(() => api.updatePerson(any())).thenAnswer(
          (_) async => _person('1', cadence: 14).copyWith(firstName: 'Saved'),
        );
        return build();
      },
      seed: () => PulseLoaded(people: [ana, ben], logs: const []),
      act: (bloc) => bloc.add(const SetCadence(personId: '1', cadenceDays: 14)),
      expect: () => [
        isA<PulseLoaded>()
            .having(
              (s) => s.people.first.contactCadenceDays,
              'optimistic cadence',
              14,
            )
            .having((s) => s.people.first.firstName, 'not yet saved', 'P1')
            .having((s) => s.people[1], 'ben untouched', same(ben)),
        isA<PulseLoaded>()
            .having((s) => s.people.first.firstName, 'saved', 'Saved')
            .having((s) => s.people.first.contactCadenceDays, 'cadence', 14),
      ],
      verify: (_) {
        final sent =
            verify(() => api.updatePerson(captureAny())).captured.single
                as Person;
        expect(sent.id, '1');
        expect(sent.contactCadenceDays, 14);
      },
    );

    blocTest<PulseBloc, PulseState>(
      'restores the original person and raises an error on failure',
      build: () {
        when(
          () => api.updatePerson(any()),
        ).thenThrow(Exception('Failed to update person'));
        return build();
      },
      seed: () =>
          PulseLoaded(people: [ana, ben], logs: const [], actionNonce: 7),
      act: (bloc) => bloc.add(const SetCadence(personId: '1', cadenceDays: 7)),
      expect: () => [
        isA<PulseLoaded>().having(
          (s) => s.people.first.contactCadenceDays,
          'optimistic',
          7,
        ),
        PulseLoaded(
          people: [ana, ben],
          logs: const [],
          actionError: 'Could not update cadence. Please try again.',
          actionNonce: 8,
        ),
      ],
    );

    blocTest<PulseBloc, PulseState>(
      'ignores an unknown person',
      build: build,
      seed: () => PulseLoaded(people: [ana], logs: const []),
      act: (bloc) => bloc.add(const SetCadence(personId: '9', cadenceDays: 7)),
      expect: () => <PulseState>[],
      verify: (_) => verifyNever(() => api.updatePerson(any())),
    );

    blocTest<PulseBloc, PulseState>(
      'is ignored until the roster has loaded',
      build: build,
      act: (bloc) => bloc.add(const SetCadence(personId: '1', cadenceDays: 7)),
      expect: () => <PulseState>[],
      verify: (_) => verifyNever(() => api.updatePerson(any())),
    );
  });

  group('state and events', () {
    test('copyWith keeps lists and nonce but drops actionError', () {
      final loaded = PulseLoaded(
        people: [_person('1')],
        logs: [_log('a', '1', jan1)],
        actionError: 'x',
        actionNonce: 2,
      );
      final copy = loaded.copyWith();
      expect(copy.people, loaded.people);
      expect(copy.logs, loaded.logs);
      expect(copy.actionNonce, 2);
      expect(copy.actionError, isNull);
    });

    test('events have value equality', () {
      expect(
        LogContact(
          personId: '1',
          channel: ContactChannel.call,
          contactedAt: jan1,
        ),
        LogContact(
          personId: '1',
          channel: ContactChannel.call,
          contactedAt: jan1,
        ),
      );
      expect(
        const SetCadence(personId: '1', cadenceDays: 7),
        isNot(const SetCadence(personId: '1', cadenceDays: 8)),
      );
      expect(LoadPulse(), LoadPulse());
      expect(const PulseError('a'), isNot(const PulseError('b')));
    });
  });
}
