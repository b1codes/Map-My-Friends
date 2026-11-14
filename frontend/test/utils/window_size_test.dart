import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/utils/window_size.dart';

/// Real device sizes in logical pixels, both orientations. The landscape phone
/// rows are the ones that matter: they are wider than a tablet in portrait,
/// which is exactly why a width-only breakpoint got them wrong.
const _cases = <String, Size>{
  'iPhone SE portrait': Size(375, 667),
  'iPhone SE landscape': Size(667, 375),
  'iPhone 14 portrait': Size(390, 844),
  'iPhone 14 landscape': Size(844, 390),
  'iPhone 14 Pro Max landscape': Size(932, 430),
  'iPad mini portrait': Size(744, 1133),
  'iPad mini landscape': Size(1133, 744),
  'iPad Pro portrait': Size(1024, 1366),
  'iPad Pro landscape': Size(1366, 1024),
  'desktop window': Size(1440, 900),
};

/// Every phone, in either orientation, must take the bar.
const _phones = {
  'iPhone SE portrait',
  'iPhone SE landscape',
  'iPhone 14 portrait',
  'iPhone 14 landscape',
  'iPhone 14 Pro Max landscape',
};

void main() {
  group('navigation shape', () {
    _cases.forEach((name, size) {
      test(name, () {
        final window = MapWindow(size);
        final expected = _phones.contains(name) ? NavShape.bar : NavShape.rail;

        expect(
          window.navShape,
          expected,
          reason:
              '$name is ${size.width}x${size.height}; a rail needs sustained '
              'vertical room, which landscape phones do not have',
        );
      });
    });

    test('a landscape phone is wider than a portrait tablet', () {
      // The premise of the bug, stated as a test so the reasoning survives.
      const phone = MapWindow(Size(844, 390));
      const tablet = MapWindow(Size(744, 1133));

      expect(phone.size.width, greaterThan(tablet.size.width));
      expect(phone.navShape, NavShape.bar);
      expect(tablet.navShape, NavShape.rail);
    });

    test('width alone never decides the shape', () {
      // Same width, different heights, different answers.
      expect(const MapWindow(Size(900, 400)).navShape, NavShape.bar);
      expect(const MapWindow(Size(900, 800)).navShape, NavShape.rail);
    });
  });

  group('content width', () {
    test('is a width-only question, unlike navigation', () {
      // A landscape phone has room to pad and cap a column even though it has
      // no room for a rail. Conflating these is what broke the shell.
      const landscapePhone = MapWindow(Size(844, 390));

      expect(landscapePhone.isWide, isTrue);
      expect(landscapePhone.usesRail, isFalse);
    });

    test('a portrait phone is neither', () {
      const portrait = MapWindow(Size(390, 844));
      expect(portrait.isWide, isFalse);
      expect(portrait.usesBar, isTrue);
    });
  });

  group('chrome insets', () {
    test('leave room for the bar only when the bar is there', () {
      expect(const MapWindow(Size(844, 390)).navBarInset, greaterThan(0));
      expect(const MapWindow(Size(1024, 1366)).navBarInset, 0);
    });

    test('preserve the incumbent map-chrome offsets', () {
      // Portrait phone chrome sat at 112 and the modal-open state at 268;
      // tablet at 24 and 180. Those numbers are behaviour, not trivia.
      const phone = MapWindow(Size(390, 844));
      const tablet = MapWindow(Size(1024, 1366));

      expect(24 + phone.navBarInset, 112);
      expect(180 + phone.navBarInset, 268);
      expect(24 + tablet.navBarInset, 24);
      expect(180 + tablet.navBarInset, 180);
    });

    test('edge inset widens only where there is width', () {
      expect(const MapWindow(Size(390, 844)).edgeInset, 16);
      expect(const MapWindow(Size(844, 390)).edgeInset, 24);
    });
  });

  testWidgets('reads the ambient window', (tester) async {
    late MapWindow seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(844, 390)),
        child: Builder(
          builder: (context) {
            seen = MapWindow.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(seen.navShape, NavShape.bar);
  });

  group('short height', () {
    test('is decided by height alone', () {
      expect(const MapWindow(Size(844, 390)).isShortHeight, isTrue);
      expect(const MapWindow(Size(390, 844)).isShortHeight, isFalse);
      expect(const MapWindow(Size(2000, 599)).isShortHeight, isTrue);
      expect(const MapWindow(Size(100, 600)).isShortHeight, isFalse);
    });
  });

  test('thresholds are inclusive', () {
    const exact = MapWindow(Size(600, 600));
    expect(exact.isWide, isTrue);
    expect(exact.usesRail, isTrue);
    expect(exact.navBarInset, 0);
    expect(const MapWindow(Size(599.9, 900)).isWide, isFalse);
    expect(const MapWindow(Size(599.9, 900)).usesBar, isTrue);
  });

  test('windows of the same size are equal', () {
    const a = MapWindow(Size(390, 844));
    const b = MapWindow(Size(390, 844));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const MapWindow(Size(844, 390))));
    expect(a == Object(), isFalse);
  });
}
