import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/custom_text_form_field.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/image_editor_modal.dart';
import 'package:map_my_friends/components/shared/nav_label.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/sample_image.dart';
import '../../../support/stage.dart';

// --- CustomTextFormField ------------------------------------------------------

@widgetbook.UseCase(
  name: 'Playground',
  type: CustomTextFormField,
  path: '[Components]/shared',
)
Widget customTextFormFieldPlayground(BuildContext context) {
  final label = context.knobs.string(label: 'Label', initialValue: 'City');
  final obscure = context.knobs.boolean(label: 'Obscure', initialValue: false);
  final readOnly = context.knobs.boolean(
    label: 'Read only',
    initialValue: false,
  );
  final maxLines = context.knobs.int.slider(
    label: 'Max lines',
    initialValue: 1,
    min: 1,
    max: 5,
  );
  final prefix = context.knobs.boolean(
    label: 'Prefix icon',
    initialValue: true,
  );
  final suffix = context.knobs.boolean(
    label: 'Suffix icon',
    initialValue: false,
  );

  return Stage(
    child: GlassContainer(
      child: CustomTextFormField(
        labelText: label,
        obscureText: obscure,
        readOnly: readOnly,
        // An obscured field must be single-line; the framework asserts on it.
        maxLines: obscure ? 1 : maxLines,
        prefixIcon: prefix ? const Icon(Icons.location_city_outlined) : null,
        suffixIcon: suffix ? const Icon(Icons.clear) : null,
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Validation error',
  type: CustomTextFormField,
  path: '[Components]/shared',
)
Widget customTextFormFieldError(BuildContext context) {
  return Stage(
    child: GlassContainer(
      child: Form(
        autovalidateMode: AutovalidateMode.always,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomTextFormField(
              labelText: 'First name',
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: MapSpacing.sm),
            CustomTextFormField(
              labelText: 'Password',
              obscureText: true,
              validator: (_) => 'Must be at least 8 characters',
            ),
          ],
        ),
      ),
    ),
  );
}

// --- NavLabel -----------------------------------------------------------------

@widgetbook.UseCase(
  name: 'In a rail slot',
  type: NavLabel,
  path: '[Components]/shared',
)
Widget navLabelInSlot(BuildContext context) {
  final label = context.knobs.string(label: 'Label', initialValue: 'People');
  final selected = context.knobs.boolean(label: 'Selected', initialValue: true);
  final scheme = Theme.of(context).colorScheme;
  final color = selected ? scheme.primary : scheme.onSurfaceVariant;

  // The 60pt slot the desktop rail gives each tab. Raise "Text scale" to see
  // the label stop at kNavLabelMaxScale while the rest of the app grows.
  return Stage(
    child: Center(
      child: GlassContainer(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: MapSpacing.md),
        child: Center(
          child: SizedBox(
            width: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, color: color),
                const SizedBox(height: 4),
                NavLabel(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// --- ImageEditorModal ---------------------------------------------------------

@widgetbook.UseCase(
  name: 'Profile picture',
  type: ImageEditorModal,
  path: '[Components]/shared',
)
Widget imageEditorModalProfile(BuildContext context) {
  final circular = context.knobs.boolean(
    label: 'Circular overlay',
    initialValue: true,
  );

  // Pushed, as from Me: Cancel and Save both pop it.
  return Stage.pushed(
    pushedFrom: 'Me',
    child: FutureBuilder(
      future: samplePortraitPng(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return const PulseIndicator();
        return ImageEditorModal(imageBytes: bytes, isCircular: circular);
      },
    ),
  );
}
