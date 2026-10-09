import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/thermal_button.dart';
import 'package:map_my_friends/components/shared/thermal_response.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/stage.dart';

const _icons = <IconData>[
  Icons.add,
  Icons.save_outlined,
  Icons.delete_outline,
  Icons.route_outlined,
];

String _iconLabel(IconData icon) => switch (icon) {
  Icons.add => 'Add',
  Icons.save_outlined => 'Save',
  Icons.delete_outline => 'Delete',
  _ => 'Route',
};

// --- ThermalButton ------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Playground',
  type: ThermalButton,
  path: '[Components]/shared',
)
Widget thermalButtonPlayground(BuildContext context) {
  final label = context.knobs.string(label: 'Label', initialValue: 'Save');
  final tone = context.knobs.object.dropdown(
    label: 'Tone',
    options: ThermalButtonTone.values,
    labelBuilder: (t) => t.name,
  );
  final icon = context.knobs.objectOrNull.dropdown(
    label: 'Icon',
    options: _icons,
    labelBuilder: _iconLabel,
  );
  final enabled = context.knobs.boolean(label: 'Enabled', initialValue: true);
  final loading = context.knobs.boolean(
    label: 'Loading',
    description: 'Swaps the label for the Chromatic Pulse and blocks taps.',
    initialValue: false,
  );
  final expand = context.knobs.boolean(label: 'Expand', initialValue: false);

  return Stage(
    child: GlassContainer(
      child: Center(
        child: ThermalButton(
          label: label,
          tone: tone,
          icon: icon,
          loading: loading,
          expand: expand,
          onPressed: enabled ? () {} : null,
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Tones and states',
  type: ThermalButton,
  path: '[Components]/shared',
)
Widget thermalButtonMatrix(BuildContext context) {
  final theme = Theme.of(context);
  return Stage(
    child: GlassContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tone in ThermalButtonTone.values) ...[
            Text(tone.name, style: theme.textTheme.labelMedium),
            const SizedBox(height: MapSpacing.xs),
            Wrap(
              spacing: MapSpacing.xs,
              runSpacing: MapSpacing.xs,
              children: [
                ThermalButton(label: 'Enabled', tone: tone, onPressed: () {}),
                ThermalButton(
                  label: 'With icon',
                  icon: Icons.add,
                  tone: tone,
                  onPressed: () {},
                ),
                ThermalButton(label: 'Disabled', tone: tone, onPressed: null),
                ThermalButton(
                  label: 'Loading',
                  tone: tone,
                  loading: true,
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: MapSpacing.sm),
          ],
        ],
      ),
    ),
  );
}

// --- ThermalResponse ----------------------------------------------------------

@widgetbook.UseCase(
  name: 'Playground',
  type: ThermalResponse,
  path: '[Components]/shared',
)
Widget thermalResponsePlayground(BuildContext context) {
  final enabled = context.knobs.boolean(label: 'Enabled', initialValue: true);
  final radius = context.knobs.object.dropdown(
    label: 'Radius',
    options: const [MapGlass.radiusSm, MapGlass.radiusMd, MapGlass.radiusLg],
    initialOption: MapGlass.radiusMd,
    labelBuilder: (r) => r.toInt().toString(),
  );
  final onSurface = Theme.of(context).colorScheme.onSurface;

  return Stage(
    child: Center(
      child: ThermalResponse(
        enabled: enabled,
        borderRadius: radius,
        onTap: () {},
        child: GlassContainer(
          borderRadius: radius,
          width: 200,
          padding: const EdgeInsets.all(MapSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, color: onSurface, size: 32),
              const SizedBox(height: MapSpacing.xs),
              Text(
                'Press and hold',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'A 50ms thermal strike, a 300ms cool-down, and a spring '
                'that yields under the finger.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
