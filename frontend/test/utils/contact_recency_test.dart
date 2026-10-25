import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:map_my_friends/utils/contact_recency.dart';

Person _person({String tag = 'FRIEND', int? cadence, DateTime? lastContacted}) {
  return Person(
    id: '1',
    firstName: 'Test',
    lastName: 'Person',
    relationshipTag: tag,
    city: 'City',
    state: 'ST',
    country: 'Country',
    contactCadenceDays: cadence,
    lastContactedAt: lastContacted,
  );
}

void main() {
  final now = DateTime(2026, 7, 22);

  group('defaultCadenceForTag', () {
    test('family is tighter than friend', () {
      expect(ContactRecency.defaultCadenceForTag('FAMILY'), 14);
      expect(ContactRecency.defaultCadenceForTag('FRIEND'), 30);
    });

    test('is case-insensitive and falls back to friend cadence', () {
      expect(ContactRecency.defaultCadenceForTag('family'), 14);
      expect(ContactRecency.defaultCadenceForTag('UNKNOWN'), 30);
    });
  });

  group('never contacted', () {
    test('is silent, needs attention, and sorts to the top', () {
      final r = ContactRecency.forPerson(_person(), now: now);
      expect(r.level, RecencyLevel.silent);
      expect(r.everContacted, isFalse);
      expect(r.daysSince, isNull);
      expect(r.overdueRatio, double.infinity);
      expect(r.isAttentionNeeded, isTrue);
      expect(r.label, 'Not yet logged');
      // Falls back to the tag default cadence for display.
      expect(r.cadenceDays, 30);
    });
  });

  group('level bands (cadence 30)', () {
    ContactRecency at(int daysAgo) => ContactRecency.forPerson(
      _person(lastContacted: now.subtract(Duration(days: daysAgo))),
      now: now,
    );

    test('fresh below half a cadence', () {
      expect(at(0).level, RecencyLevel.fresh);
      expect(at(10).level, RecencyLevel.fresh); // ratio 0.33
    });

    test('steady between half and one cadence', () {
      expect(at(20).level, RecencyLevel.steady); // ratio 0.67
    });

    test('due just past cadence', () {
      expect(at(35).level, RecencyLevel.due); // ratio 1.17
      expect(at(35).isAttentionNeeded, isFalse);
    });

    test('overdue past 1.5x cadence', () {
      expect(at(60).level, RecencyLevel.overdue); // ratio 2.0
      expect(at(60).isAttentionNeeded, isTrue);
    });

    test('silent past 2.5x cadence', () {
      expect(at(90).level, RecencyLevel.silent); // ratio 3.0
      expect(at(90).everContacted, isTrue);
      expect(at(90).label, 'Long overdue');
    });
  });

  group('per-person cadence overrides tag default', () {
    test('a tight custom cadence heats up faster', () {
      final person = _person(
        tag: 'FRIEND',
        cadence: 7,
        lastContacted: now.subtract(const Duration(days: 20)),
      );
      final r = ContactRecency.forPerson(person, now: now);
      // 20 / 7 = 2.86 -> silent, whereas the friend default (30) would be steady.
      expect(r.cadenceDays, 7);
      expect(r.level, RecencyLevel.silent);
    });
  });

  group('progress and phrasing', () {
    test('progress clamps to 1.0 when overdue', () {
      final r = ContactRecency.forPerson(
        _person(lastContacted: now.subtract(const Duration(days: 90))),
        now: now,
      );
      expect(r.progress, 1.0);
    });

    test('future or same-day contact reads as today with zero days', () {
      final r = ContactRecency.forPerson(_person(lastContacted: now), now: now);
      expect(r.daysSince, 0);
      expect(r.lastContactPhrase, 'Contacted today');
    });

    test('week-scale phrasing', () {
      final r = ContactRecency.forPerson(
        _person(lastContacted: now.subtract(const Duration(days: 9))),
        now: now,
      );
      expect(r.lastContactPhrase, 'Contacted last week');
    });
  });

  ContactRecency daysAgo(int days, {int cadence = 30}) =>
      ContactRecency.fromValues(
        lastContactedAt: now.subtract(Duration(days: days)),
        cadenceDays: cadence,
        now: now,
      );

  group('lastContactPhrase', () {
    test('covers every relative band', () {
      expect(
        ContactRecency.forPerson(_person(), now: now).lastContactPhrase,
        'No contact logged yet',
      );
      expect(daysAgo(1).lastContactPhrase, 'Contacted yesterday');
      expect(daysAgo(2).lastContactPhrase, 'Contacted 2 days ago');
      expect(daysAgo(6).lastContactPhrase, 'Contacted 6 days ago');
      expect(daysAgo(7).lastContactPhrase, 'Contacted last week');
      expect(daysAgo(13).lastContactPhrase, 'Contacted last week');
      expect(daysAgo(14).lastContactPhrase, 'Contacted 2 weeks ago');
      expect(daysAgo(29).lastContactPhrase, 'Contacted 4 weeks ago');
      expect(daysAgo(30).lastContactPhrase, 'Contacted last month');
      expect(daysAgo(59).lastContactPhrase, 'Contacted last month');
      expect(daysAgo(60).lastContactPhrase, 'Contacted 2 months ago');
      expect(daysAgo(364).lastContactPhrase, 'Contacted 12 months ago');
      expect(daysAgo(365).lastContactPhrase, 'Contacted over a year ago');
    });
  });

  group('edge inputs', () {
    test('a non-positive cadence is treated as one day', () {
      final zero = daysAgo(1, cadence: 0);
      expect(zero.cadenceDays, 1);
      expect(zero.overdueRatio, 1.0);
      expect(daysAgo(0, cadence: -5).cadenceDays, 1);
      final never = ContactRecency.fromValues(
        lastContactedAt: null,
        cadenceDays: 0,
        now: now,
      );
      expect(never.cadenceDays, 1);
    });

    test('a future contact counts as today', () {
      final r = ContactRecency.fromValues(
        lastContactedAt: now.add(const Duration(days: 3)),
        cadenceDays: 30,
        now: now,
      );
      expect(r.daysSince, 0);
      expect(r.level, RecencyLevel.fresh);
      expect(r.progress, 0.0);
    });

    test('compares calendar days, not 24-hour spans', () {
      // 23:59 yesterday to 00:01 today is one calendar day.
      final r = ContactRecency.fromValues(
        lastContactedAt: DateTime(2026, 7, 21, 23, 59),
        cadenceDays: 30,
        now: DateTime(2026, 7, 22, 0, 1),
      );
      expect(r.daysSince, 1);
    });

    test('defaults "now" to the current clock', () {
      final r = ContactRecency.fromValues(
        lastContactedAt: DateTime.now().subtract(const Duration(days: 400)),
        cadenceDays: 30,
      );
      // A range, so a run that straddles midnight still passes.
      expect(r.daysSince, inInclusiveRange(400, 401));
      expect(r.level, RecencyLevel.silent);
    });

    test('progress is the fraction of the cadence used', () {
      expect(daysAgo(15).progress, closeTo(0.5, 1e-9));
    });

    test('labels for the middle bands', () {
      expect(daysAgo(0).label, 'In touch');
      expect(daysAgo(20).label, 'On track');
      expect(daysAgo(35).label, 'Due soon');
      expect(daysAgo(60).label, 'Overdue');
    });

    test('band boundaries are inclusive on the hotter side', () {
      expect(daysAgo(15).level, RecencyLevel.steady); // exactly 0.5
      expect(daysAgo(30).level, RecencyLevel.due); // exactly 1.0
      expect(daysAgo(45).level, RecencyLevel.overdue); // exactly 1.5
      expect(daysAgo(75).level, RecencyLevel.silent); // exactly 2.5
    });
  });

  group('visual mapping', () {
    final byLevel = <RecencyLevel, ContactRecency>{
      RecencyLevel.fresh: daysAgo(0),
      RecencyLevel.steady: daysAgo(20),
      RecencyLevel.due: daysAgo(35),
      RecencyLevel.overdue: daysAgo(60),
      RecencyLevel.silent: daysAgo(90),
    };

    test('each level reads on its own palette signal', () {
      expect(byLevel[RecencyLevel.fresh]!.signal, same(MapPalette.vital));
      expect(byLevel[RecencyLevel.steady]!.signal, same(MapPalette.calm));
      expect(byLevel[RecencyLevel.due]!.signal, same(MapPalette.due));
      expect(byLevel[RecencyLevel.overdue]!.signal, same(MapPalette.overdue));
      expect(byLevel[RecencyLevel.silent]!.signal, same(MapPalette.critical));
      for (final r in byLevel.values) {
        expect(r.vividColor, r.signal.vivid);
      }
    });

    test('each level has a distinct icon, and never-contacted waves', () {
      expect(byLevel[RecencyLevel.fresh]!.icon, Icons.favorite);
      expect(byLevel[RecencyLevel.steady]!.icon, Icons.check_circle);
      expect(byLevel[RecencyLevel.due]!.icon, Icons.schedule);
      expect(byLevel[RecencyLevel.overdue]!.icon, Icons.local_fire_department);
      expect(byLevel[RecencyLevel.silent]!.icon, Icons.priority_high);
      expect(
        ContactRecency.forPerson(_person(), now: now).icon,
        Icons.waving_hand,
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('ink color follows the ${brightness.name} theme', (
        tester,
      ) async {
        final theme = ThemeData(brightness: brightness);
        late BuildContext ctx;
        await tester.pumpWidget(
          Theme(
            data: theme,
            child: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        // Steady reads as ordinary text; every other level is tinted.
        expect(
          byLevel[RecencyLevel.steady]!.inkColor(ctx),
          theme.colorScheme.onSurface,
        );
        for (final level in [
          RecencyLevel.fresh,
          RecencyLevel.due,
          RecencyLevel.overdue,
          RecencyLevel.silent,
        ]) {
          final r = byLevel[level]!;
          expect(r.inkColor(ctx), r.signal.ink(brightness), reason: '$level');
        }
      });
    }
  });

  group('ContactChannelUi', () {
    test('maps each channel to an icon and a distinct marker color', () {
      expect(ContactChannel.call.icon, Icons.call);
      expect(ContactChannel.video.icon, Icons.videocam);
      expect(ContactChannel.message.icon, Icons.chat_bubble);
      expect(ContactChannel.call.markerColor, MapPalette.defaultPin);
      expect(ContactChannel.video.markerColor, MapPalette.accent);
      expect(ContactChannel.message.markerColor, MapPalette.vital.vivid);
      expect(
        ContactChannel.values.map((c) => c.markerColor).toSet(),
        hasLength(3),
      );
    });
  });
}
