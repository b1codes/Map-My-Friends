import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

/// The two platform accessibility settings this design system answers to.
typedef MediaPreferences = ({bool reduceMotion, bool highContrast});

/// Toggles reduced motion and high contrast for the entry under review.
///
/// Both change what the app draws, not just how fast it draws it: reduced
/// motion freezes the Ambient Field on `MapField.stillPhase` and drops the
/// Chromatic Pulse to a static mark, and high contrast swaps refractive glass
/// for an opaque surface with a hard edge. Each is a separate visual contract
/// worth reviewing, and neither is reachable from Widgetbook's stock addons.
class MediaPreferencesAddon extends WidgetbookAddon<MediaPreferences> {
  MediaPreferencesAddon() : super(name: 'Motion & contrast');

  @override
  List<Field> get fields => [
    BooleanField(name: 'reduceMotion', initialValue: false),
    BooleanField(name: 'highContrast', initialValue: false),
  ];

  @override
  MediaPreferences valueFromQueryGroup(Map<String, String> group) {
    return (
      reduceMotion: valueOf<bool>('reduceMotion', group) ?? false,
      highContrast: valueOf<bool>('highContrast', group) ?? false,
    );
  }

  @override
  Widget buildUseCase(
    BuildContext context,
    Widget child,
    MediaPreferences setting,
  ) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: setting.reduceMotion,
        highContrast: setting.highContrast,
      ),
      child: child,
    );
  }
}
