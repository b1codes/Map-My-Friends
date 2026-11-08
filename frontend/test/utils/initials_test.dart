import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/utils/initials.dart';

void main() {
  group('initialOf', () {
    test('takes the first letter', () {
      expect(initialOf('Grace'), 'G');
    });

    test('is empty for an empty, blank or missing name', () {
      expect(initialOf(''), '');
      expect(initialOf('   '), '');
      expect(initialOf(null), '');
    });

    test('ignores leading spaces', () {
      expect(initialOf('  Ada'), 'A');
    });

    // name[0] is one UTF-16 code unit: half of each of these.
    for (final (name, initial) in [
      ('🦄✨', '🦄'),
      ('👩🏽‍💻 coder', '👩🏽‍💻'),
      ('🇮🇪 Dublin', '🇮🇪'),
      ('𝓐lice', '𝓐'),
      ('émile', 'é'),
      ('نور', 'ن'),
      ('李', '李'),
    ]) {
      test('takes the whole first character of "$name"', () {
        expect(initialOf(name), initial);
        // A lone surrogate is what made painting throw.
        expect(
          initialOf(name).runes.every((r) => r < 0xD800 || r > 0xDFFF),
          isTrue,
        );
      });
    }
  });

  test('initialsOf joins first and last', () {
    expect(initialsOf('Grace', 'Hopper'), 'GH');
    expect(initialsOf('🦄', '👩🏽‍💻'), '🦄👩🏽‍💻');
    expect(initialsOf('Cher', ''), 'C');
    expect(initialsOf(null, 'Ng'), 'N');
  });
}
