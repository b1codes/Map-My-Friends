import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/components/map/custom_map_marker.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/image_editor_modal.dart';
import 'package:map_my_friends/l10n/app_localizations.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/screens/people/add_edit_person_screen.dart';
import 'package:map_my_friends/services/api_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

class MockPeopleBloc extends MockBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {}

class MockApiService extends Mock implements ApiService {}

const _imagePickerChannel = MethodChannel('plugins.flutter.io/image_picker');

/// A valid 1x1 transparent PNG, so the crop editor can decode it.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

Airport _airport(int id, String iata) => Airport(
  id: id,
  name: '$iata Airport',
  iataCode: iata,
  airportType: 'large_airport',
  city: 'City',
  country: 'US',
  latitude: 45,
  longitude: -122,
);

Station _station(int id, String name) =>
    Station(id: id, name: name, osmId: id, latitude: 45, longitude: -122);

final _pdx = _airport(1, 'PDX');
final _sea = _airport(2, 'SEA');
final _union = _station(10, 'Union Station');
final _lloyd = _station(11, 'Lloyd Center');

final _existing = Person(
  id: 'p1',
  firstName: 'Ann',
  lastName: 'Lee',
  relationshipTag: 'FAMILY',
  city: 'Portland',
  state: 'OR',
  country: 'USA',
  street: '1 Main St',
  phoneNumber: '5035550100',
  birthday: DateTime(1990, 1, 2),
  latitude: 45.52,
  longitude: -122.68,
  timezone: 'America/Los_Angeles',
  pinColor: '#00FF00',
  pinStyle: 'circle',
  pinIconType: 'initials',
  preferredAirportId: '1',
  preferredAirport: _pdx,
  preferredStation: _union,
  preferredStationId: '10',
);

void main() {
  late MockPeopleBloc peopleBloc;
  late MockApiService api;
  late List<MethodCall> pickerCalls;
  late Future<Object?> Function(MethodCall call) pickerReply;

  setUpAll(() {
    tzdata.initializeTimeZones();
    registerFallbackValue(LoadPeople());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    peopleBloc = MockPeopleBloc();
    api = MockApiService();
    when(() => peopleBloc.state).thenReturn(PeopleLoaded([_existing]));
    when(
      () => api.getNearestAirports(any(), any()),
    ).thenAnswer((_) async => [_pdx, _sea]);
    when(
      () => api.getNearestStations(any(), any()),
    ).thenAnswer((_) async => [_union, _lloyd]);

    pickerCalls = [];
    pickerReply = (_) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePickerChannel, (call) {
          pickerCalls.add(call);
          return pickerReply(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePickerChannel, null);
  });

  /// Pushes the form over a placeholder home, so popping it is observable.
  Future<void> pumpForm(
    WidgetTester tester, {
    Person? person,
    double width = 600,
  }) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider<PeopleBloc>.value(
        value: peopleBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AddEditPersonScreen(person: person, apiService: api),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(field('First Name'), 'Cy');
    await tester.enterText(field('Last Name'), 'Oh');
    await tester.enterText(field('City (Required)'), 'Austin');
    await tester.enterText(field('State (Required)'), 'TX');
    await tester.enterText(field('Country (Required)'), 'USA');
  }

  Future<void> choose(WidgetTester tester, String current, String next) async {
    await tester.tap(find.text(current).last);
    await _settle(tester);
    await tester.tap(find.text(next).last);
    await _settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save Person'));
    await _settle(tester);
  }

  Person dispatchedAdd() {
    final event =
        verify(() => peopleBloc.add(captureAny())).captured.single as AddPerson;
    return event.person;
  }

  UpdatePerson dispatchedUpdate() =>
      verify(() => peopleBloc.add(captureAny())).captured.single
          as UpdatePerson;

  group('adding', () {
    testWidgets('starts empty with sensible defaults', (tester) async {
      await pumpForm(tester);

      expect(find.text('Add Person'), findsOneWidget);
      expect(find.text('Friend'), findsOneWidget);
      expect(find.text('Select Date'), findsOneWidget);
      expect(find.text('Preferred Transit Hubs'), findsNothing);
      expect(find.textContaining('Local Time'), findsNothing);
      final pin = tester.widget<CustomMapMarker>(find.byType(CustomMapMarker));
      expect(pin.pinColorHex, '#F44336');
      expect(pin.pinStyle, 'teardrop');
      expect(pin.pinIconType, 'none');
      verifyNever(() => api.getNearestAirports(any(), any()));
    });

    testWidgets('will not save until every required field is filled', (
      tester,
    ) async {
      await pumpForm(tester);

      await save(tester);

      expect(find.text('Required'), findsNWidgets(5));
      verifyNever(() => peopleBloc.add(any()));
      expect(find.byType(AddEditPersonScreen), findsOneWidget);
    });

    testWidgets('saves the required fields as a new person and closes', (
      tester,
    ) async {
      await pumpForm(tester);
      await fillRequired(tester);

      await save(tester);

      final person = dispatchedAdd();
      expect(person.id, '');
      expect(person.firstName, 'Cy');
      expect(person.lastName, 'Oh');
      expect(person.relationshipTag, 'FRIEND');
      expect(person.city, 'Austin');
      expect(person.state, 'TX');
      expect(person.country, 'USA');
      // Blank optional fields are sent as absent, not as empty strings.
      expect(person.street, isNull);
      expect(person.phoneNumber, isNull);
      expect(person.birthday, isNull);
      expect(person.pinColor, '#F44336');
      expect(person.pinStyle, 'teardrop');
      expect(person.pinIconType, 'none');
      expect(person.pinEmoji, isNull);
      expect(person.latitude, isNull);
      expect(find.byType(AddEditPersonScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('sends the optional fields and the chosen tag and pin', (
      tester,
    ) async {
      await pumpForm(tester);
      await fillRequired(tester);
      await tester.enterText(field('Street Address (Optional)'), '9 Elm');
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone Number (Optional)'),
        '2025550123',
      );
      await choose(tester, 'Friend', 'Family');
      await choose(tester, 'Teardrop', 'Diamond');
      await choose(tester, 'None', 'Initials');

      // The preview follows the form.
      final pin = tester.widget<CustomMapMarker>(find.byType(CustomMapMarker));
      expect(pin.pinStyle, 'diamond');
      expect(pin.pinIconType, 'initials');
      expect(pin.initials, 'CO');

      await save(tester);

      final person = dispatchedAdd();
      expect(person.relationshipTag, 'FAMILY');
      expect(person.street, '9 Elm');
      expect(person.phoneNumber, endsWith('2025550123'));
      expect(person.pinStyle, 'diamond');
      expect(person.pinIconType, 'initials');
      expect(person.pinEmoji, isNull);
    });

    testWidgets('an emoji pin defaults to a smiley and keeps the emoji', (
      tester,
    ) async {
      await pumpForm(tester);
      await fillRequired(tester);
      expect(find.text('Selected Emoji'), findsNothing);

      await choose(tester, 'None', 'Emoji');

      expect(find.text('Selected Emoji'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Selected Emoji'),
          matching: find.text('😀'),
        ),
        findsOneWidget,
      );
      // The preview draws the same emoji.
      expect(
        tester.widget<CustomMapMarker>(find.byType(CustomMapMarker)).pinEmoji,
        '😀',
      );

      await save(tester);

      final person = dispatchedAdd();
      expect(person.pinIconType, 'emoji');
      expect(person.pinEmoji, '😀');
    });

    testWidgets('choosing from the emoji picker replaces the emoji', (
      tester,
    ) async {
      await pumpForm(tester);
      await fillRequired(tester);
      await choose(tester, 'None', 'Emoji');

      await tester.tap(_swatch('Selected Emoji'));
      await _settle(tester);
      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.byIcon(Icons.tag_faces));
      await _settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(EmojiPicker),
          matching: find.text('😂'),
        ),
      );
      await _settle(tester);

      expect(find.byType(EmojiPicker), findsNothing);
      await save(tester);
      expect(dispatchedAdd().pinEmoji, '😂');
    });

    testWidgets('picking a colour in the colour dialog recolours the pin', (
      tester,
    ) async {
      await pumpForm(tester);
      await fillRequired(tester);

      await tester.tap(find.text('Pin Color'));
      await _settle(tester);
      // Opened from the swatch itself, not the row label.
      expect(find.text('Pick a Pin Color'), findsNothing);
      await tester.tap(_swatch('Pin Color'));
      await _settle(tester);
      expect(find.text('Pick a Pin Color'), findsOneWidget);

      // BlockPicker's second swatch is Material pink.
      await tester.tap(
        find
            .descendant(
              of: find.byType(BlockPicker),
              matching: find.byType(InkWell),
            )
            .at(1),
      );
      await tester.pump();
      await tester.tap(find.text('Got it'));
      await _settle(tester);

      expect(find.text('Pick a Pin Color'), findsNothing);
      expect(
        tester
            .widget<CustomMapMarker>(find.byType(CustomMapMarker))
            .pinColorHex,
        '#E91E63',
      );

      await save(tester);
      expect(dispatchedAdd().pinColor, '#E91E63');
    });

    testWidgets('the birthday comes from the date picker', (tester) async {
      await pumpForm(tester);
      await fillRequired(tester);

      await tester.tap(find.text('Select Date'));
      await _settle(tester);
      // Day 1 of the current month is always selectable (lastDate is today).
      await tester.tap(find.text('1').first);
      await tester.pump();
      await tester.tap(find.text('OK'));
      await _settle(tester);

      final now = DateTime.now();
      final expected = DateTime(now.year, now.month, 1);
      expect(
        find.text(expected.toLocal().toString().split(' ')[0]),
        findsOneWidget,
      );

      await save(tester);
      expect(dispatchedAdd().birthday, expected);
    });

    testWidgets('cancelling the date picker leaves the birthday unset', (
      tester,
    ) async {
      await pumpForm(tester);

      await tester.tap(find.text('Select Date'));
      await _settle(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      expect(find.text('Select Date'), findsOneWidget);
    });

    testWidgets('Back closes the form without saving', (tester) async {
      await pumpForm(tester);
      await fillRequired(tester);

      await tester.tap(find.byTooltip('Back'));
      await _settle(tester);

      expect(find.byType(AddEditPersonScreen), findsNothing);
      verifyNever(() => peopleBloc.add(any()));
    });

    testWidgets('a second tap on Save while saving does not save twice', (
      tester,
    ) async {
      await pumpForm(tester);
      await fillRequired(tester);

      await tester.tap(find.text('Save Person'));
      await tester.tap(find.text('Save Person'), warnIfMissed: false);
      await _settle(tester);

      verify(() => peopleBloc.add(any(that: isA<AddPerson>()))).called(1);
    });
  });

  group('photo', () {
    Future<void> openPhotoSheet(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.camera_alt).first);
      await _settle(tester);
    }

    testWidgets('offers gallery and camera, but no removal for a new person', (
      tester,
    ) async {
      await pumpForm(tester);

      await openPhotoSheet(tester);

      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Take a Photo'), findsOneWidget);
      expect(find.text('Remove Photo'), findsNothing);
    });

    for (final c in <(String, int)>[
      ('Choose from Gallery', 1),
      ('Take a Photo', 0),
    ]) {
      testWidgets('"${c.$1}" asks the picker for that source, sized for a '
          'profile', (tester) async {
        await pumpForm(tester);
        await openPhotoSheet(tester);

        await tester.tap(find.text(c.$1));
        await _settle(tester);

        final args = pickerCalls.single.arguments as Map;
        expect(pickerCalls.single.method, 'pickImage');
        expect(args['source'], c.$2);
        expect(args['maxWidth'], 1024);
        expect(args['maxHeight'], 1024);
        expect(args['imageQuality'], 90);
        // Cancelling the picker changes nothing.
        expect(find.byType(ImageEditorModal), findsNothing);
      });
    }

    testWidgets('a picker failure is reported, not thrown', (tester) async {
      pickerReply = (_) async =>
          throw PlatformException(code: 'no_access', message: 'denied');
      // Wide enough for the whole message: long toasts overflow (reported
      // separately against GlassToast).
      await pumpForm(tester, width: 1600);
      await openPhotoSheet(tester);

      await tester.tap(find.text('Choose from Gallery'));
      await _settle(tester);

      expect(find.textContaining('Failed to pick image:'), findsOneWidget);
      expect(find.textContaining('denied'), findsOneWidget);
    });

    testWidgets('a picked and cropped photo is uploaded with the person', (
      tester,
    ) async {
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('add_edit_person_test'),
      );
      addTearDown(() => dir!.deleteSync(recursive: true));
      final file = File('${dir!.path}/pick.png');
      await tester.runAsync(() => file.writeAsBytes(_png));
      pickerReply = (_) async => file.path;

      await pumpForm(tester);
      await fillRequired(tester);
      await openPhotoSheet(tester);
      // Reading the picked file is real I/O, which only completes outside
      // the fake clock, so the tap that starts it runs on the real one.
      await tester.runAsync(() async {
        await tester.tap(find.text('Choose from Gallery'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _settle(tester);

      final editor = tester.widget<ImageEditorModal>(
        find.byType(ImageEditorModal),
      );
      expect(editor.imageBytes, _png);
      expect(editor.isCircular, isTrue);

      // Finish the crop with a known result.
      // A copy, so the upload can be told apart from the picked original.
      final cropped = Uint8List.fromList(_png);
      Navigator.of(tester.element(find.byType(ImageEditorModal))).pop(cropped);
      await _settle(tester);
      // The picker flow awaiting the editor resumes on the real clock too.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);

      final avatar = tester.widget<CircleAvatar>(
        find.byType(CircleAvatar).first,
      );
      expect(avatar.backgroundImage, isA<MemoryImage>());

      await save(tester);

      final event =
          verify(() => peopleBloc.add(captureAny())).captured.single
              as AddPerson;
      expect(event.imageBytes, same(cropped));
      expect(event.profileImage, isNull);
    });
  });

  group('editing', () {
    testWidgets('prefills every field from the person', (tester) async {
      await pumpForm(tester, person: _existing);

      expect(find.text('Edit Person'), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('Lee'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('1 Main St'), findsOneWidget);
      expect(find.text('Portland'), findsOneWidget);
      expect(find.text('OR'), findsOneWidget);
      expect(find.text('USA'), findsOneWidget);
      expect(find.text('5035550100'), findsOneWidget);
      expect(find.text('1990-01-02'), findsOneWidget);
      expect(find.textContaining('Local Time: '), findsOneWidget);
      expect(find.text('Circle'), findsOneWidget);
      expect(find.text('Initials'), findsOneWidget);
      final pin = tester.widget<CustomMapMarker>(find.byType(CustomMapMarker));
      expect(pin.pinColorHex, '#00FF00');
      expect(pin.initials, 'AL');
    });

    testWidgets('saving updates the same person and keeps what was not '
        'edited', (tester) async {
      await pumpForm(tester, person: _existing);
      await tester.enterText(field('First Name'), 'Annie');

      await save(tester);

      final event = dispatchedUpdate();
      final person = event.person;
      expect(person.id, 'p1');
      expect(person.firstName, 'Annie');
      expect(person.lastName, 'Lee');
      expect(person.relationshipTag, 'FAMILY');
      expect(person.street, '1 Main St');
      expect(person.phoneNumber, '5035550100');
      expect(person.birthday, DateTime(1990, 1, 2));
      expect((person.latitude, person.longitude), (45.52, -122.68));
      expect(person.pinColor, '#00FF00');
      expect(person.pinStyle, 'circle');
      expect(person.pinIconType, 'initials');
      expect(person.preferredAirportId, '1');
      expect(person.preferredStationId, '10');
      expect(event.imageBytes, isNull);
      expect(find.byType(AddEditPersonScreen), findsNothing);
    });

    testWidgets('an unknown timezone hides the local time', (tester) async {
      await pumpForm(
        tester,
        person: _existing.copyWith(timezone: 'Nowhere/Special'),
      );

      expect(find.textContaining('Local Time'), findsNothing);
      expect(find.text('Edit Person'), findsOneWidget);
    });

    testWidgets('an existing photo can be removed', (tester) async {
      await _primeNetworkImage(tester, 'https://img.test/ann.png');
      await pumpForm(
        tester,
        person: _existing.copyWith(profileImageUrl: 'https://img.test/ann.png'),
      );

      await tester.tap(find.byIcon(Icons.camera_alt).first);
      await _settle(tester);
      await tester.tap(find.text('Remove Photo'));
      await _settle(tester);

      final avatar = tester.widget<CircleAvatar>(
        find.byType(CircleAvatar).first,
      );
      expect(avatar.backgroundImage, isNull);
      expect(
        tester
            .widget<CustomMapMarker>(find.byType(CustomMapMarker))
            .profileImageUrl,
        isNull,
      );

      await save(tester);
      expect(dispatchedUpdate().person.profileImageUrl, isNull);
    });
  });

  group('nearby hubs', () {
    testWidgets('loads hubs near the person and preselects their choices', (
      tester,
    ) async {
      await pumpForm(tester, person: _existing);

      verify(() => api.getNearestAirports(45.52, -122.68)).called(1);
      verify(() => api.getNearestStations(45.52, -122.68)).called(1);
      expect(find.text('Preferred Transit Hubs'), findsOneWidget);
      expect(find.text('PDX Airport (PDX)'), findsOneWidget);
      expect(find.text('Union Station'), findsOneWidget);
    });

    testWidgets('choosing different hubs saves them', (tester) async {
      await pumpForm(tester, person: _existing);

      await choose(tester, 'PDX Airport (PDX)', 'SEA Airport (SEA)');
      await choose(tester, 'Union Station', 'Lloyd Center');
      await save(tester);

      final person = dispatchedUpdate().person;
      expect(person.preferredAirportId, '2');
      expect(person.preferredAirport, same(_sea));
      expect(person.preferredStationId, '11');
      expect(person.preferredStation, same(_lloyd));
    });

    testWidgets('a saved hub that is no longer nearby is shown as a hint', (
      tester,
    ) async {
      when(
        () => api.getNearestAirports(any(), any()),
      ).thenAnswer((_) async => [_sea]);
      when(
        () => api.getNearestStations(any(), any()),
      ).thenAnswer((_) async => [_lloyd]);
      await pumpForm(tester, person: _existing);

      expect(find.text('PDX Airport'), findsOneWidget);
      expect(find.text('Union Station'), findsOneWidget);

      await save(tester);
      // Not having it in the list does not drop the saved choice.
      expect(dispatchedUpdate().person.preferredAirportId, '1');
    });

    testWidgets('without saved hubs the dropdowns ask for one', (tester) async {
      final noHubs = Person(
        id: 'p9',
        firstName: 'Bo',
        lastName: 'Ng',
        relationshipTag: 'FRIEND',
        city: 'Austin',
        state: 'TX',
        country: 'USA',
        latitude: 30.27,
        longitude: -97.74,
      );
      await pumpForm(tester, person: noHubs);

      expect(find.text('Select Preferred Airport'), findsOneWidget);
      expect(find.text('Select Preferred Station'), findsOneWidget);
    });

    testWidgets('shows a loading indicator until the hubs arrive', (
      tester,
    ) async {
      final airports = Completer<List<Airport>>();
      when(
        () => api.getNearestAirports(any(), any()),
      ).thenAnswer((_) => airports.future);
      await pumpForm(tester, person: _existing);

      expect(find.byType(PulseIndicator), findsOneWidget);
      expect(find.text('Refresh Nearby Hubs'), findsNothing);

      airports.complete([_pdx]);
      await _settle(tester);

      expect(find.byType(PulseIndicator), findsNothing);
      expect(find.text('Refresh Nearby Hubs'), findsOneWidget);
    });

    // Regression: neither setState after the hub fetch checked `mounted`, so
    // going Back before the hubs arrived threw "setState() called after
    // dispose()" whether the fetch then succeeded or failed.
    for (final outcome in ['succeeds', 'fails']) {
      testWidgets('leaving before the hub load $outcome does not throw', (
        tester,
      ) async {
        final airports = Completer<List<Airport>>();
        when(
          () => api.getNearestAirports(any(), any()),
        ).thenAnswer((_) => airports.future);
        await pumpForm(tester, person: _existing);

        await tester.tap(find.byTooltip('Back'));
        await _settle(tester);
        expect(find.byType(AddEditPersonScreen), findsNothing);

        if (outcome == 'succeeds') {
          airports.complete([_pdx]);
        } else {
          airports.completeError(Exception('offline'));
        }
        await _settle(tester);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a failed load is reported and the form stays usable', (
      tester,
    ) async {
      when(
        () => api.getNearestAirports(any(), any()),
      ).thenAnswer((_) async => throw Exception('offline'));
      await pumpForm(tester, person: _existing);

      expect(
        find.text('Failed to load hubs: Exception: offline'),
        findsOneWidget,
      );
      expect(find.byType(PulseIndicator), findsNothing);
      expect(find.text('Refresh Nearby Hubs'), findsOneWidget);
    });

    testWidgets('Refresh Nearby Hubs loads them again', (tester) async {
      await pumpForm(tester, person: _existing);

      await tester.tap(find.text('Refresh Nearby Hubs'));
      await _settle(tester);

      verify(() => api.getNearestAirports(45.52, -122.68)).called(2);
      verify(() => api.getNearestStations(45.52, -122.68)).called(2);
    });

    testWidgets('a person without coordinates has no hub section', (
      tester,
    ) async {
      final unlocated = Person(
        id: 'p8',
        firstName: 'Di',
        lastName: 'Ko',
        relationshipTag: 'FRIEND',
        city: 'Nowhere',
        state: 'NA',
        country: 'NA',
      );
      await pumpForm(tester, person: unlocated);

      expect(find.text('Preferred Transit Hubs'), findsNothing);
      verifyNever(() => api.getNearestAirports(any(), any()));
      verifyNever(() => api.getNearestStations(any(), any()));
    });
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// The tappable colour swatch at the end of the [label] row.
Finder _swatch(String label) => find
    .descendant(
      of: find.widgetWithText(ListTile, label),
      matching: find.byType(GestureDetector),
    )
    .last;

/// Puts a decoded image for [url] in the image cache, so a [NetworkImage] of
/// it resolves without the network.
Future<void> _primeNetworkImage(WidgetTester tester, String url) async {
  final image = await tester.runAsync(() => createTestImage());
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(url),
    () => OneFrameImageStreamCompleter(
      SynchronousFuture(ImageInfo(image: image!)),
    ),
  );
  addTearDown(PaintingBinding.instance.imageCache.clear);
}
