import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

/// A write's `done`, with its outcome recorded as soon as it settles (an
/// error with no listener yet would otherwise escape the test).
class _Outcome {
  _Outcome() {
    done.future.then<void>(
      (_) => saved = true,
      onError: (Object e) {
        error = e;
      },
    );
  }

  final done = Completer<void>();
  bool saved = false;
  Object? error;
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakePerson());
  });

  late ApiService apiService;
  late PeopleBloc peopleBloc;

  final testPerson = Person(
    id: '1',
    firstName: 'John',
    lastName: 'Doe',
    relationshipTag: 'Friend',
    city: 'New York',
    state: 'NY',
    country: 'USA',
    latitude: 40.7128,
    longitude: -74.0060,
  );

  final testPeople = [testPerson];

  setUp(() {
    apiService = MockApiService();
    peopleBloc = PeopleBloc(apiService: apiService);
  });

  tearDown(() {
    peopleBloc.close();
  });

  group('PeopleBloc', () {
    test('initial state is PeopleInitial', () {
      expect(peopleBloc.state, PeopleInitial());
    });

    group('LoadPeople', () {
      blocTest<PeopleBloc, PeopleState>(
        'emits [PeopleLoading, PeopleLoaded] on success',
        build: () {
          when(
            () => apiService.getPeople(),
          ).thenAnswer((_) async => testPeople);
          return peopleBloc;
        },
        act: (bloc) => bloc.add(LoadPeople()),
        expect: () => [PeopleLoading(), PeopleLoaded(testPeople)],
      );

      blocTest<PeopleBloc, PeopleState>(
        'emits [PeopleLoading, PeopleError] on failure',
        build: () {
          when(
            () => apiService.getPeople(),
          ).thenThrow(Exception('Failed to load'));
          return peopleBloc;
        },
        act: (bloc) => bloc.add(LoadPeople()),
        expect: () => [
          PeopleLoading(),
          const PeopleError('Exception: Failed to load'),
        ],
      );
    });

    group('AddPerson', () {
      final newPerson = Person(
        id: '2',
        firstName: 'Jane',
        lastName: 'Doe',
        relationshipTag: 'Family',
        city: 'Los Angeles',
        state: 'CA',
        country: 'USA',
        latitude: 34.0522,
        longitude: -118.2437,
      );

      blocTest<PeopleBloc, PeopleState>(
        'emits [PeopleLoaded] with new person on success',
        build: () {
          when(
            () => apiService.addPerson(any()),
          ).thenAnswer((_) async => newPerson);
          return peopleBloc;
        },
        seed: () => PeopleLoaded(testPeople),
        act: (bloc) => bloc.add(AddPerson(newPerson)),
        expect: () => [
          PeopleLoaded([...testPeople, newPerson]),
        ],
      );

      // A failed save used to replace the list with PeopleError: People
      // showed "Couldn't load your people" with no retry until the app
      // restarted. Found by the edge-case tests (offline save).
      late _Outcome failed;
      blocTest<PeopleBloc, PeopleState>(
        'keeps the list and reports a failure to the caller',
        build: () {
          when(
            () => apiService.addPerson(any()),
          ).thenThrow(Exception('Failed to add'));
          return peopleBloc;
        },
        seed: () => PeopleLoaded(testPeople),
        act: (bloc) =>
            bloc.add(AddPerson(newPerson, done: (failed = _Outcome()).done)),
        expect: () => <PeopleState>[],
        verify: (_) => expect(failed.error, isA<Exception>()),
      );

      late _Outcome saved;
      blocTest<PeopleBloc, PeopleState>(
        'tells the caller once the person is saved',
        build: () {
          when(
            () => apiService.addPerson(any()),
          ).thenAnswer((_) async => newPerson);
          return peopleBloc;
        },
        seed: () => PeopleLoaded(testPeople),
        act: (bloc) =>
            bloc.add(AddPerson(newPerson, done: (saved = _Outcome()).done)),
        expect: () => [
          PeopleLoaded([...testPeople, newPerson]),
        ],
        verify: (_) => expect(saved.saved, isTrue),
      );

      // Events run concurrently. Each save used to write back the list it
      // started with, so the slower of two saves dropped the faster's person.
      final third = newPerson.copyWith(id: '3', firstName: 'Jim');
      blocTest<PeopleBloc, PeopleState>(
        'two saves in flight at once both end up in the list',
        build: () {
          when(() => apiService.addPerson(newPerson)).thenAnswer(
            (_) => Future.delayed(
              const Duration(milliseconds: 20),
              () => newPerson,
            ),
          );
          when(() => apiService.addPerson(third)).thenAnswer(
            (_) => Future.delayed(const Duration(milliseconds: 5), () => third),
          );
          return peopleBloc;
        },
        seed: () => PeopleLoaded(testPeople),
        act: (bloc) => bloc
          ..add(AddPerson(newPerson))
          ..add(AddPerson(third)),
        wait: const Duration(milliseconds: 50),
        expect: () => [
          PeopleLoaded([...testPeople, third]),
          PeopleLoaded([...testPeople, third, newPerson]),
        ],
      );
    });

    group('UpdatePerson', () {
      final updatedPerson = testPerson.copyWith(firstName: 'Johnny');

      blocTest<PeopleBloc, PeopleState>(
        'emits [PeopleLoaded] with updated person on success',
        build: () {
          when(
            () => apiService.updatePerson(any()),
          ).thenAnswer((_) async => updatedPerson);
          return peopleBloc;
        },
        seed: () => PeopleLoaded(testPeople),
        act: (bloc) => bloc.add(UpdatePerson(updatedPerson)),
        expect: () => [
          PeopleLoaded([updatedPerson]),
        ],
      );

      late _Outcome failed;
      blocTest<PeopleBloc, PeopleState>(
        'keeps the list and reports a failure to the caller',
        build: () {
          when(
            () => apiService.updatePerson(any()),
          ).thenThrow(Exception('Failed to update'));
          return peopleBloc;
        },
        seed: () => PeopleLoaded(testPeople),
        act: (bloc) => bloc.add(
          UpdatePerson(updatedPerson, done: (failed = _Outcome()).done),
        ),
        expect: () => <PeopleState>[],
        verify: (_) => expect(failed.error, isA<Exception>()),
      );
    });

    group('DeletePerson', () {
      blocTest<PeopleBloc, PeopleState>(
        'emits [PeopleLoaded] without deleted person on success',
        build: () {
          when(() => apiService.deletePerson('1')).thenAnswer((_) async {});
          return peopleBloc;
        },
        seed: () => PeopleLoaded(testPeople),
        act: (bloc) => bloc.add(const DeletePerson('1')),
        expect: () => [const PeopleLoaded([])],
      );

      late _Outcome failed;
      blocTest<PeopleBloc, PeopleState>(
        'keeps the list and reports a failure to the caller',
        build: () {
          when(
            () => apiService.deletePerson('1'),
          ).thenThrow(Exception('Failed to delete'));
          return peopleBloc;
        },
        seed: () => PeopleLoaded(testPeople),
        act: (bloc) =>
            bloc.add(DeletePerson('1', done: (failed = _Outcome()).done)),
        expect: () => <PeopleState>[],
        verify: (_) => expect(failed.error, isA<Exception>()),
      );
    });

    // A change made before the list arrived (or after it failed to load)
    // used to be refused or silently dropped. It now goes to the API, and
    // the list is loaded with it.
    group('before the list has loaded', () {
      final added = testPerson.copyWith(id: '9', firstName: 'Late');

      blocTest<PeopleBloc, PeopleState>(
        'AddPerson saves, then loads the list with the new person',
        build: () {
          when(
            () => apiService.addPerson(any()),
          ).thenAnswer((_) async => added);
          when(
            () => apiService.getPeople(),
          ).thenAnswer((_) async => [testPerson, added]);
          return peopleBloc;
        },
        act: (bloc) => bloc.add(AddPerson(added)),
        expect: () => [
          PeopleLoading(),
          PeopleLoaded([testPerson, added]),
        ],
      );

      blocTest<PeopleBloc, PeopleState>(
        'UpdatePerson saves, then loads the list',
        build: () {
          when(
            () => apiService.updatePerson(any()),
          ).thenAnswer((_) async => testPerson);
          when(
            () => apiService.getPeople(),
          ).thenAnswer((_) async => testPeople);
          return peopleBloc;
        },
        seed: () => PeopleLoading(),
        act: (bloc) => bloc.add(UpdatePerson(testPerson)),
        // Already loading, so the reload's PeopleLoading isn't a change.
        expect: () => [PeopleLoaded(testPeople)],
      );

      blocTest<PeopleBloc, PeopleState>(
        'DeletePerson deletes, then loads the list',
        build: () {
          when(() => apiService.deletePerson('1')).thenAnswer((_) async {});
          when(() => apiService.getPeople()).thenAnswer((_) async => []);
          return peopleBloc;
        },
        seed: () => const PeopleError('earlier failure'),
        act: (bloc) => bloc.add(const DeletePerson('1')),
        expect: () => [PeopleLoading(), const PeopleLoaded([])],
      );
    });

    group('image uploads', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final file = XFile('/tmp/avatar.png');

      blocTest<PeopleBloc, PeopleState>(
        'AddPerson forwards the picked image and its bytes',
        build: () {
          when(
            () => apiService.addPerson(
              any(),
              profileImage: any(named: 'profileImage'),
              imageBytes: any(named: 'imageBytes'),
            ),
          ).thenAnswer((_) async => testPerson);
          return peopleBloc;
        },
        seed: () => const PeopleLoaded([]),
        act: (bloc) => bloc.add(
          AddPerson(testPerson, profileImage: file, imageBytes: bytes),
        ),
        expect: () => [
          PeopleLoaded([testPerson]),
        ],
        verify: (_) => verify(
          () => apiService.addPerson(
            testPerson,
            profileImage: file,
            imageBytes: bytes,
          ),
        ).called(1),
      );

      blocTest<PeopleBloc, PeopleState>(
        'UpdatePerson forwards the image bytes',
        build: () {
          when(
            () => apiService.updatePerson(
              any(),
              profileImage: any(named: 'profileImage'),
              imageBytes: any(named: 'imageBytes'),
            ),
          ).thenAnswer((_) async => testPerson);
          return peopleBloc;
        },
        seed: () => PeopleLoaded([testPerson]),
        act: (bloc) => bloc.add(UpdatePerson(testPerson, imageBytes: bytes)),
        verify: (_) => verify(
          () => apiService.updatePerson(
            testPerson,
            profileImage: null,
            imageBytes: bytes,
          ),
        ).called(1),
      );
    });

    blocTest<PeopleBloc, PeopleState>(
      'UpdatePerson replaces only the matching person, keeping order',
      build: () {
        when(() => apiService.updatePerson(any())).thenAnswer(
          (_) async => testPerson.copyWith(id: '2', firstName: 'Updated'),
        );
        return peopleBloc;
      },
      seed: () => PeopleLoaded([
        testPerson,
        testPerson.copyWith(id: '2'),
        testPerson.copyWith(id: '3'),
      ]),
      act: (bloc) => bloc.add(UpdatePerson(testPerson.copyWith(id: '2'))),
      expect: () => [
        isA<PeopleLoaded>()
            .having((s) => s.people.map((p) => p.id), 'ids', ['1', '2', '3'])
            .having((s) => s.people.map((p) => p.firstName), 'names', [
              'John',
              'Updated',
              'John',
            ]),
      ],
    );

    test('events and states have value equality', () {
      expect(AddPerson(testPerson), AddPerson(testPerson));
      expect(UpdatePerson(testPerson), UpdatePerson(testPerson));
      expect(const DeletePerson('1'), isNot(const DeletePerson('2')));
      expect(LoadPeople(), LoadPeople());
      expect(
        const PeopleOperationSuccess('Saved'),
        const PeopleOperationSuccess('Saved'),
      );
      expect(
        const PeopleOperationSuccess('Saved'),
        isNot(const PeopleOperationSuccess('Deleted')),
      );
    });
  });
}

// Add a fallback for Mocktail so 'any()' works with Person
class FakePerson extends Fake implements Person {}

// Need to call this in main or setUp
void setupFallbacks() {
  registerFallbackValue(FakePerson());
}
