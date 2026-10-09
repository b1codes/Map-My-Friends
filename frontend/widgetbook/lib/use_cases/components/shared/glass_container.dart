import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/stage.dart';

const _radii = <double>[
  MapGlass.radiusSm,
  MapGlass.radiusMd,
  MapGlass.radiusLg,
];

String _radiusLabel(double r) => switch (r) {
  MapGlass.radiusSm => 'Sm · ${r.toInt()}',
  MapGlass.radiusMd => 'Md · ${r.toInt()}',
  _ => 'Lg · ${r.toInt()}',
};

Widget _copy(BuildContext context, String title, String body) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: theme.textTheme.titleLarge),
      const SizedBox(height: MapSpacing.xs),
      Text(body, style: theme.textTheme.bodyMedium),
    ],
  );
}

@widgetbook.UseCase(
  name: 'Playground',
  type: GlassContainer,
  path: '[Components]/shared',
)
Widget glassContainerPlayground(BuildContext context) {
  final radius = context.knobs.object.dropdown(
    label: 'Radius',
    options: _radii,
    initialOption: MapGlass.radiusLg,
    labelBuilder: _radiusLabel,
  );
  final blur = context.knobs.double.slider(
    label: 'Blur sigma',
    initialValue: MapGlass.blurSigma,
    max: 40,
    divisions: 40,
  );
  final opacity = context.knobs.double.slider(
    label: 'Tint opacity',
    description:
        'Clamped by the material to ${MapGlass.tintMin}–'
        '${MapGlass.tintMax - MapGlass.sheen}; past that it stops reading '
        'as glass.',
    initialValue: MapGlass.tintLight,
    max: 0.3,
    divisions: 30,
    precision: 2,
  );
  final title = context.knobs.string(
    label: 'Title',
    initialValue: 'Refractive Glass',
  );

  return Stage(
    child: GlassContainer(
      borderRadius: radius,
      blur: blur,
      opacity: opacity,
      padding: const EdgeInsets.all(MapSpacing.md),
      child: _copy(
        context,
        title,
        'Depth by refraction, never by shadow. The field drifting behind '
        'this panel is what makes its edge read as an edge.',
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Grouped panels',
  type: GlassContainer,
  path: '[Components]/shared',
)
Widget glassContainerGrouped(BuildContext context) {
  return Stage(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassContainer(
          child: _copy(
            context,
            'One sample, many panels',
            'Every grouped panel under the same BackdropGroup shares one '
                'backdrop sample, so a screen of chrome costs one filter '
                'layer.',
          ),
        ),
        const SizedBox(height: MapSpacing.sm),
        Row(
          children: [
            for (final radius in _radii) ...[
              Expanded(
                child: GlassContainer(
                  borderRadius: radius,
                  height: 96,
                  child: Center(
                    child: Text(
                      _radiusLabel(radius),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              ),
              if (radius != _radii.last) const SizedBox(width: MapSpacing.xs),
            ],
          ],
        ),
      ],
    ),
  );
}

@widgetbook.UseCase(
  name: 'Isolated (over other glass)',
  type: GlassContainer,
  path: '[Components]/shared',
)
Widget glassContainerIsolated(BuildContext context) {
  return Stage(
    child: SizedBox(
      height: 320,
      child: Stack(
        children: [
          Positioned.fill(
            child: GlassContainer(
              child: _copy(
                context,
                'Grouped panel',
                'Chrome laid out on the canvas samples the shared backdrop.',
              ),
            ),
          ),
          Positioned(
            left: MapSpacing.md,
            right: MapSpacing.md,
            bottom: MapSpacing.md,
            child: GlassContainer.isolated(
              borderRadius: MapGlass.radiusMd,
              child: _copy(
                context,
                'Isolated panel',
                'A surface that sits over other glass owns its own sample; '
                    'two overlapping grouped panels would render as one.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
