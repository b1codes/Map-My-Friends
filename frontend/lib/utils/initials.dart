import 'package:flutter/widgets.dart';

/// The first character of [name] as a reader sees it (one grapheme cluster,
/// so a whole emoji, flag or accented letter), or '' for an empty name.
///
/// Not `name[0]`: that's one UTF-16 code unit, which for an emoji is half of
/// a surrogate pair. Painting a lone surrogate throws ("string is not
/// well-formed UTF-16"), so a friend named 🦄 broke every screen that drew
/// their avatar.
String initialOf(String? name) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? '' : trimmed.characters.first;
}

/// [first]'s initial followed by [last]'s, e.g. 'GH' for Grace Hopper.
String initialsOf(String? first, String? last) =>
    initialOf(first) + initialOf(last);
