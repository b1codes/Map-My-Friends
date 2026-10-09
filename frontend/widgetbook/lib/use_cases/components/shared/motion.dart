import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/ambient_field.dart';
import 'package:map_my_friends/components/shared/ambient_scaffold.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/glass_header.dart';
import 'package:map_my_friends/components/shared/glass_inlay.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/stage.dart';

// --- AmbientField -------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Full bleed',
  type: AmbientField,
  path: '[Components]/shared',
)
Widget ambientFieldFullBleed(BuildContext context) {
  // Nothing on top: the room every glass surface refracts, on its own. Toggle
  // "Motion & contrast" to see the still phase the reduced-motion path shows.
  return const Stage.route(child: SizedBox.expand(child: AmbientField()));
}

// --- AmbientScaffold ----------------------------------------------------------

@widgetbook.UseCase(
  name: 'With header',
  type: AmbientScaffold,
  path: '[Components]/shared',
)
Widget ambientScaffoldWithHeader(BuildContext context) {
  final appearance = context.knobs.objectOrNull.dropdown(
    label: 'Appearance',
    description:
        'Forces a brightness regardless of the app theme, for surfaces that '
        'must read one way (the image editor, the map).',
    options: Brightness.values,
    labelBuilder: (b) => b.name,
  );

  return Stage.pushed(
    pushedFrom: 'Me',
    child: AmbientScaffold(
      appearance: appearance,
      header: const GlassHeader(
        title: 'Settings',
        subtitle: 'A pushed route brings its own room',
      ),
      body: ListView(
        padding: const EdgeInsets.all(MapSpacing.md),
        children: [
          for (final label in ['Appearance', 'Map', 'Location', 'About'])
            Padding(
              padding: const EdgeInsets.only(bottom: MapSpacing.sm),
              child: GlassContainer(
                borderRadius: MapGlass.radiusMd,
                child: Text(label),
              ),
            ),
        ],
      ),
    ),
  );
}

// --- ChromaticPulse -----------------------------------------------------------

@widgetbook.UseCase(
  name: 'Playground',
  type: ChromaticPulse,
  path: '[Components]/shared',
)
Widget chromaticPulsePlayground(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final duration = context.knobs.duration(
    label: 'Cycle',
    initialValue: MapMotion.chromaticCycle,
  );
  final radius = context.knobs.double.slider(
    label: 'Border radius',
    initialValue: MapGlass.radiusSm,
    max: MapGlass.radiusLg,
  );
  final size = context.knobs.double.slider(
    label: 'Size',
    initialValue: 120,
    min: 16,
    max: 240,
  );

  return Stage(
    child: Center(
      child: SizedBox.square(
        dimension: size,
        child: ChromaticPulse(
          colors: [scheme.primary, scheme.secondary, MapPalette.thermalCorona],
          duration: duration,
          borderRadius: radius,
        ),
      ),
    ),
  );
}

// --- PulseIndicator -----------------------------------------------------------

@widgetbook.UseCase(
  name: 'Playground',
  type: PulseIndicator,
  path: '[Components]/shared',
)
Widget pulseIndicatorPlayground(BuildContext context) {
  final size = context.knobs.double.slider(
    label: 'Size',
    initialValue: 28,
    min: 12,
    max: 96,
  );
  final label = context.knobs.stringOrNull(
    label: 'Semantics label',
    initialValue: 'Loading people',
  );

  return Stage(
    child: GlassContainer(
      height: 200,
      child: PulseIndicator(size: size, label: label),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Inline in a row',
  type: PulseIndicator,
  path: '[Components]/shared',
)
Widget pulseIndicatorInline(BuildContext context) {
  return Stage(
    child: GlassContainer(
      child: GlassInlay(
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: PulseIndicator(size: 20, centered: false),
            ),
            const SizedBox(width: MapSpacing.sm),
            Expanded(
              child: Text(
                'Finding airports near Rome…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
