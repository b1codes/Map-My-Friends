// Accounts: signing up, signing in, staying signed in, and signing out, with
// username/password accounts on the real API. Auth0 (Google, Apple, Unified
// Sign In) redirects to a hosted login page and is on the manual QA
// checklist instead (docs/manual-qa.md).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:map_my_friends/components/people/person_card.dart';

import '../support/e2e.dart';

/// The form's submit button; the screen's title says 'Create Account' too.
final createAccountButton = find.widgetWithText(FilledButton, 'Create Account');

void main() {
  setUpE2E();

  group('Accounts', () {
    journey('a new user signs up, signs in, is remembered, and signs out', (
      tester,
    ) async {
      final user = JourneyUser.fresh('signup');

      await launchApp(tester);
      await pumpUntil(tester, loginScreen);
      await tapText(tester, 'Sign Up');
      await pumpUntil(tester, find.text('Join Map My Friends'));

      await enterField(tester, 'Username *', user.username);
      await enterField(tester, 'Email *', user.email);
      await enterField(tester, 'First Name', 'Journey');
      await enterField(tester, 'Last Name', 'Tester');
      await enterField(tester, 'Password *', journeyPassword);
      await enterField(tester, 'Confirm Password *', journeyPassword);
      await tapOn(tester, createAccountButton);

      // Signing up doesn't sign in: it returns to the login form.
      await pumpUntil(tester, loginScreen, reason: 'the login form');
      await pumpUntilGone(tester, find.text('Join Map My Friends'));

      await signInThroughUi(tester, user.username);

      // The Me tab is filled from the profile the API holds for this user.
      await goToTab(tester, 'Me');
      await pumpUntil(
        tester,
        find.descendant(
          of: field('First Name'),
          matching: find.text('Journey'),
        ),
        reason: 'the first name entered at sign-up on the Me tab',
      );

      // Coming back to the app later skips the login form.
      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell, reason: 'the shell on relaunch');
      expect(loginScreen, findsNothing);

      await goToTab(tester, 'Me');
      await tapText(tester, 'Logout');
      await pumpUntil(tester, loginScreen);

      // Signing out forgets the session for the next launch too.
      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(
        tester,
        loginScreen,
        reason: 'the login form on relaunch',
      );
      expect(mainShell, findsNothing);
    });

    journey('a wrong password is refused and nothing is signed in', (
      tester,
    ) async {
      final user = await JourneyUser.registered('wrongpw');

      await launchApp(tester);
      await pumpUntil(tester, loginScreen);
      await enterField(tester, 'Username', user.username);
      await enterField(tester, 'Password', 'not-the-password');
      await tapOn(tester, loginScreen);

      await pumpUntil(tester, toast('Invalid username or password'));
      expect(mainShell, findsNothing);

      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, loginScreen);
    });

    journey('signing up with a taken username shows the API\'s reason', (
      tester,
    ) async {
      final existing = await JourneyUser.registered('taken');

      await launchApp(tester);
      await pumpUntil(tester, loginScreen);
      await tapText(tester, 'Sign Up');
      await enterField(tester, 'Username *', existing.username);
      await enterField(tester, 'Email *', 'someone.else@example.com');
      await enterField(tester, 'Password *', journeyPassword);
      await enterField(tester, 'Confirm Password *', journeyPassword);
      await tapOn(tester, createAccountButton);

      await pumpUntil(tester, toast('username'));
      // Still on the sign-up form, with what was typed kept.
      expect(find.text('Join Map My Friends'), findsOneWidget);
      expect(find.text(existing.username), findsOneWidget);
    });

    journey('a forgotten password can be reset by email', (tester) async {
      final user = await JourneyUser.registered('forgot');

      await launchApp(tester);
      await pumpUntil(tester, loginScreen);
      await tapText(tester, 'Forgot Password?');
      await enterField(tester, 'Email', user.email);
      await tapText(tester, 'Send Reset Link');

      await pumpUntil(tester, toast('a password reset link has been sent'));
      await pumpUntil(tester, loginScreen, reason: 'the login form');
    });
    journey(
      'after signing out, the next account sees none of the last one\'s data',
      (tester) async {
        final first = await JourneyUser.registered('switchfrom');
        await first.addPerson(firstName: 'Grace', lastName: 'Hopper');
        await (await first.api()).post(
          'trips/',
          data: {
            'name': 'Visit Grace',
            'date': '2026-11-14',
            'status': 'DRAFT',
            'stops': <Object>[],
            'legs': <Object>[],
          },
        );
        final second = await JourneyUser.registered('switchto');

        // The first account uses People, Trips and the planner.
        await launchSignedIn(tester, first);
        await goToTab(tester, 'People');
        await tapOn(
          tester,
          find.ancestor(
            of: find.text('Grace Hopper'),
            matching: find.byType(PersonCard),
          ),
        );
        await tapText(tester, 'Add to Trip Planner');
        await pumpUntil(tester, toast('to trip'));
        await tapOn(tester, find.byTooltip('Back'));
        await goToTab(tester, 'Trips');
        await pumpUntil(tester, find.text('Visit Grace'));

        // Same browser tab, no reload: sign out, then in as someone else.
        await goToTab(tester, 'Me');
        await tapText(tester, 'Logout');
        await signInThroughUi(tester, second.username);

        await goToTab(tester, 'People');
        await pumpUntil(tester, find.text('No Friends Added Yet'));
        expect(find.text('Grace Hopper'), findsNothing);

        await goToTab(tester, 'Trips');
        await pumpUntil(tester, find.text('No Trips Yet'));
        expect(find.text('Visit Grace'), findsNothing);

        // The planner the first account left behind isn't carried over.
        await goToTab(tester, 'Map');
        expect(find.bySemanticsLabel('Save Trip'), findsNothing);
      },
    );
  });
}
