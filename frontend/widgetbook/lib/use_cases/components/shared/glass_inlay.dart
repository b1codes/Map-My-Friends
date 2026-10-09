import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/glass_inlay.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/stage.dart';

@widgetbook.UseCase(
  name: 'Playground',
  type: GlassInlay,
  path: '[Components]/shared',
)
Widget glassInlayPlayground(BuildContext context) {
  final strong = context.knobs.boolean(label: 'Strong', initialValue: false);
  final edge = context.knobs.boolean(label: 'Edge', initialValue: true);
  final radius = context.knobs.object.dropdown(
    label: 'Radius',
    options: const [MapGlass.radiusSm, MapGlass.radiusMd],
    initialOption: MapGlass.radiusMd,
    labelBuilder: (r) => r.toInt().toString(),
  );
  final label = context.knobs.string(
    label: 'Label',
    initialValue: 'Set into the panel — no blur of its own',
  );
  final onSurface = Theme.of(context).colorScheme.onSurface;

  return Stage(
    child: GlassContainer(
      child: GlassInlay(
        strong: strong,
        edge: edge,
        borderRadius: radius,
        child: Row(
          children: [
            GlassInlay(
              strong: true,
              edge: false,
              borderRadius: MapGlass.radiusSm,
              padding: const EdgeInsets.all(MapSpacing.xs),
              child: Icon(Icons.person_outline, color: onSurface),
            ),
            const SizedBox(width: MapSpacing.sm),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Variants',
  type: GlassInlay,
  path: '[Components]/shared',
)
Widget glassInlayVariants(BuildContext context) {
  Widget row(String label, {bool strong = false, bool edge = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MapSpacing.xs),
      child: GlassInlay(strong: strong, edge: edge, child: Text(label)),
    );
  }

  return Stage(
    child: GlassContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('Default'),
          row('Strong', strong: true),
          row('No edge', edge: false),
          row('Strong, no edge', strong: true, edge: false),
        ],
      ),
    ),
  );
}
