import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';

/// The layer every glass surface refracts.
///
/// [GlassContainer] blurs what sits behind it, which means a flat scaffold
/// colour makes the material vanish — blurring one colour returns that colour.
/// The Map tab always had a live tile scene to distort; every other surface had
/// `Colors.grey[50]`, and the depth work fell to Material's tonal roles by
/// default. This is the scene the rest of the app was missing.
///
/// Four soft masses drift on closed Lissajous orbits over a near-neutral
/// ground. Nothing here is meant to be looked at directly: the field earns its
/// place at the edge of a glass panel, where a slowly moving luminance
/// gradient is what makes a refractive edge legible as an edge.
///
/// Paint order matters. The field must sit *below* the screen and its chrome
/// inside the same [BackdropGroup], so the group's single backdrop sample
/// includes it. It costs no `BackdropFilter` layer of its own.
class AmbientField extends StatefulWidget {
  const AmbientField({super.key});

  @override
  State<AmbientField> createState() => _AmbientFieldState();
}

class _AmbientFieldState extends State<AmbientField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;
  late final AppLifecycleListener _lifecycle;

  /// Whether the app is foregrounded. A field drifting behind a backgrounded
  /// app still forces every glass surface above it to re-blur, which is real
  /// battery for pixels nobody is looking at.
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(vsync: this, duration: MapField.cycle);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _syncDrift();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDrift();
  }

  /// Reduced motion freezes the composition rather than removing it: the field
  /// is what the glass is *made legible by*, so deleting it would flatten the
  /// whole interface for the users who asked only for stillness.
  ///
  /// High contrast stops it for a different reason — that path paints one flat
  /// ground and never reads the phase, so a running controller would be ticks
  /// spent on a value nothing consumes.
  bool get _shouldDrift {
    final media = MediaQuery.of(context);
    return _foreground && !media.disableAnimations && !media.highContrast;
  }

  void _syncDrift() {
    if (!mounted) return;
    if (_shouldDrift) {
      if (!_drift.isAnimating) _drift.repeat();
    } else if (_drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // High contrast has no use for atmosphere, and GlassContainer's opaque
    // path is already the surface in that mode. Give it one flat ground.
    if (MediaQuery.of(context).highContrast) {
      return ExcludeSemantics(
        child: ColoredBox(color: MapField.ground(brightness)),
      );
    }

    final Widget painted = AnimatedBuilder(
      animation: _drift,
      builder: (context, _) {
        // Quantised so a sub-pixel move does not repaint the field and, with
        // it, re-blur every glass surface layered above.
        final steps = MapField.driftSteps;
        final phase = _drift.isAnimating || _drift.value != 0.0
            ? _drift.value
            : MapField.stillPhase;
        return CustomPaint(
          painter: _FieldPainter(
            phase: (phase * steps).floorToDouble() / steps,
            brightness: brightness,
          ),
          isComplex: true,
          willChange: _drift.isAnimating,
          size: Size.infinite,
        );
      },
    );

    return ExcludeSemantics(child: RepaintBoundary(child: painted));
  }
}

class _FieldPainter extends CustomPainter {
  final double phase;
  final Brightness brightness;

  const _FieldPainter({required this.phase, required this.brightness});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final isDark = brightness == Brightness.dark;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark ? MapField.groundDark : MapField.groundLight,
        ).createShader(rect),
    );

    // Masses are clipped to the surface: a radial shader is cheap, but letting
    // one paint a full-screen rect beyond its own circle is not.
    canvas.save();
    canvas.clipRect(rect);
    for (final mass in MapField.masses) {
      _paintMass(canvas, size, mass, isDark);
    }
    canvas.restore();
  }

  void _paintMass(Canvas canvas, Size size, FieldMass mass, bool isDark) {
    final turnsX = 2 * math.pi * (mass.cyclesX * phase + mass.phaseX);
    final turnsY = 2 * math.pi * (mass.cyclesY * phase + mass.phaseY);

    final center = Offset(
      size.width * (mass.center.dx + mass.amplitude.dx * math.sin(turnsX)),
      size.height * (mass.center.dy + mass.amplitude.dy * math.cos(turnsY)),
    );
    final radius = mass.radiusFactor * size.longestSide;
    final alpha = mass.alpha(brightness);

    final paint = Paint()
      // Additive in the void so overlapping masses read as light meeting
      // light. In daylight the same blend would blow out to white, so the
      // masses tint the ground instead.
      ..blendMode = isDark ? BlendMode.plus : BlendMode.srcOver
      ..shader =
          RadialGradient(
            colors: <Color>[
              mass.color.withValues(alpha: alpha),
              mass.color.withValues(alpha: alpha * 0.42),
              mass.color.withValues(alpha: 0.0),
            ],
            stops: const <double>[0.0, 0.45, 1.0],
          ).createShader(
            Rect.fromCircle(center: center, radius: math.max(radius, 1.0)),
          );

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_FieldPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.brightness != brightness;
}
