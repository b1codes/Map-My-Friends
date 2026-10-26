// The Me tab and Settings: profile edits are saved to the account (they
// follow the user to a new device), while Settings are kept on the device.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';

import '../support/e2e.dart';

/// The Me tab's Save button (the toast says 'Profile Saved', not this).
final saveProfileButton = find.widgetWithText(FilledButton, 'Save Profile');

/// The selection of the only segmented control of type [T] on screen.
Set<T> selectedSegment<T>(WidgetTester tester) =>
    tester.widget<SegmentedButton<T>>(find.byType(SegmentedButton<T>)).selected;

/// Whether [label]'s text field currently holds [value].
Finder fieldHolding(String label, String value) =>
    find.descendant(of: field(label), matching: find.text(value));

/// Fills the Me tab's required address, which its form validates on save.
Future<void> enterHomeAddress(WidgetTester tester) async {
  await enterField(tester, 'City (Required)', 'Boston');
  await enterField(tester, 'State (Required)', 'MA');
  await enterField(tester, 'Country (Required)', 'USA');
}

Future<void> saveProfile(WidgetTester tester) async {
  await tapOn(tester, saveProfileButton);
  await pumpUntil(tester, toast('Profile Saved'));
  // The button shows a pulse while the request is in flight.
  await pumpUntil(tester, saveProfileButton, reason: 'the save to finish');
}

/// Opens Settings from the Me tab's header.
Future<void> openSettings(WidgetTester tester) async {
  await goToTab(tester, 'Me');
  await tapOn(tester, find.byTooltip('Settings'));
  await pumpUntil(tester, find.text('Default Map Settings'));
}

void main() {
  setUpE2E();

  group('Profile', () {
    journey('profile edits are saved to the account and follow the user', (
      tester,
    ) async {
      final user = await JourneyUser.registered('profile', firstName: 'Pat');

      await launchSignedIn(tester, user);
      await goToTab(tester, 'Me');
      await pumpUntil(tester, fieldHolding('First Name', 'Pat'));

      await enterField(tester, 'First Name', 'Morgan');
      await enterField(tester, 'Last Name', 'Rivera');
      await enterHomeAddress(tester);
      await tapText(tester, 'Imperial (mi)');
      await tapText(tester, 'Teardrop'); // opens the Pin Shape menu
      await tapOn(tester, find.text('Diamond').last);
      await settle(tester);
      await saveProfile(tester);

      final saved = (await (await user.api()).get('user/profile/')).data;
      expect(saved['first_name'], 'Morgan');
      expect(saved['last_name'], 'Rivera');
      expect(saved['city'], 'Boston');
      expect(saved['distance_unit'], 'imperial');
      expect(saved['pin_style'], 'diamond');

      // A different device: nothing local, so all of it comes from the API.
      await launchSignedIn(tester, user);
      await goToTab(tester, 'Me');
      await pumpUntil(tester, fieldHolding('First Name', 'Morgan'));
      expect(fieldHolding('Last Name', 'Rivera'), findsOneWidget);
      expect(fieldHolding('City (Required)', 'Boston'), findsOneWidget);
      expect(selectedSegment<String>(tester), {'imperial'});
      expect(find.text('Diamond'), findsOneWidget);
    });

    journey('the account distance unit changes the distances shown', (
      tester,
    ) async {
      final user = await JourneyUser.registered('units');
      await user.addPerson(firstName: 'Alan', lastName: 'Turing');

      await launchSignedIn(tester, user);
      await goToTab(tester, 'Me');
      await enterHomeAddress(tester);
      await tapText(tester, 'Imperial (mi)');
      await saveProfile(tester);

      await goToTab(tester, 'Map');
      await tapOn(tester, pinOf('Alan Turing'));
      await tapText(tester, 'Alan Turing');

      // Nearby airports for the person, measured in miles now.
      await pumpUntil(tester, find.text('SFO'), reason: 'SFO near the person');
      expect(find.textContaining(RegExp(r'\d mi$')), findsWidgets);
      expect(find.textContaining(RegExp(r'\d km$')), findsNothing);
    });
  });

  group('Settings', () {
    journey('map settings stay on this device across relaunches', (
      tester,
    ) async {
      final user = await JourneyUser.registered('settings');

      await launchSignedIn(tester, user);
      expect(find.bySemanticsLabel('Zoom In'), findsWidgets);

      await openSettings(tester);
      await tapText(tester, 'Minimal');
      await tapText(tester, 'Show Map Controls');
      await settle(tester);
      expect(selectedSegment<MapType>(tester), {MapType.minimal});
      await goBack(tester);

      // The map follows straight away: no zoom or pan controls.
      await goToTab(tester, 'Map');
      expect(find.bySemanticsLabel('Zoom In'), findsNothing);

      // Reopening the app on this device keeps both.
      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell);
      await settle(tester);
      expect(find.bySemanticsLabel('Zoom In'), findsNothing);
      await openSettings(tester);
      expect(selectedSegment<MapType>(tester), {MapType.minimal});
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );

      // They're device settings, not account ones: a new device has defaults.
      await launchSignedIn(tester, user);
      expect(find.bySemanticsLabel('Zoom In'), findsWidgets);
      await openSettings(tester);
      expect(selectedSegment<MapType>(tester), {MapType.standard});
    });

    journey(
      'the app theme chosen in Settings survives a relaunch',
      (tester) async {
        ThemeMode appTheme() =>
            tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

        final user = await JourneyUser.registered('theme');

        await launchSignedIn(tester, user);
        await openSettings(tester);
        // 'Dark' is in both Appearance (first) and Minimal Map Theme.
        await tapOn(tester, find.text('Dark').first);
        await settle(tester);
        expect(appTheme(), ThemeMode.dark);

        await launchApp(tester, keepDeviceState: true);
        await pumpUntil(tester, mainShell);
        expect(appTheme(), ThemeMode.dark);
      },
      skip:
          'Known bug: ThemeCubit keeps the app theme in memory only, so '
          'it resets to System on every launch (ClickUp 86bcrpgxf)',
    );
  });
}
