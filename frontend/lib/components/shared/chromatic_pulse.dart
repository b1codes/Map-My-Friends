import 'dart:math';

import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';

/// The LLC loading signature: a synchronized colour breathe through the app's
/// own palette.
///
/// Waiting is not idle. Thermal Glow answers "how does the interface respond
/// when touched"; this answers "how does it behave while the user waits" — the
/// machine thinking, not the machine stalled. It replaces every
/// `CircularProgressIndicator` in the app, which is Material's answer to the
/// same question and belongs to a different product.
///
/// Palette-agnostic by design (unlike Thermal Heat, which is fixed): the colour
/// array comes from the consuming surface, never from hardcoded brand values.
/// See `llc-standards/context/chromatic-pulse.md` for the constants this
/// implements and [MapMotion] for the interaction curves it deliberately does
/// *not* reuse.
class ChromaticPulse extends StatefulWidget {
  final List<Color> colors;
  final Duration duration;
  final double borderRadius;

  const ChromaticPulse({
    super.key,
    required this.colors,
    this.duration = MapMotion.chromaticCycle,
    this.borderRadius = MapGlass.radiusSm,
  });

  @override
  State<ChromaticPulse> createState() => _ChromaticPulseState();
}

class _ChromaticPulseState extends State<ChromaticPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _eased;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    // Checked here rather than in the constructor's initialiser list: a const
    // list of Colors cannot be evaluated at compile time, so an assert there
    // makes `const ChromaticPulse(...)` fail to compile — which is exactly how
    // most of this widget's call sites want to be written.
    assert(
      widget.colors.length >= 2,
      'ChromaticPulse interpolates between palette entries and needs at '
      'least two',
    );
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _eased = CurvedAnimation(parent: _controller, curve: MapMotion.chromatic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: inherited widgets are not guaranteed
    // available that early.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion && !_hasStarted) {
      _controller.repeat();
      _hasStarted = true;
    } else if (reduceMotion && _hasStarted) {
      _controller.stop();
      _hasStarted = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Walks the palette as a closed loop, so the cycle returns to its first
  /// colour rather than jumping there.
  Color _colorAt(double t) {
    final loop = [...widget.colors, widget.colors.first];
    final segmentCount = loop.length - 1;
    final scaled = t * segmentCount;
    final index = min(scaled.floor(), segmentCount - 1);
    return Color.lerp(loop[index], loop[index + 1], scaled - index)!;
  }

  @override
  Widget build(BuildContext context) {
    // This loop can run for the whole length of a slow load — far longer than
    // Thermal Glow's momentary lifecycle — so an unsatisfied reduced-motion
    // setting is disruptive here in a way it is nowhere else in the app.
    if (MediaQuery.disableAnimationsOf(context)) {
      return RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.colors.first,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _eased,
        builder: (context, child) {
          // Maps the eased progress onto the 0.55-1.0 opacity range as one
          // full breath per palette cycle, whatever the palette's length.
          final opacity = 0.775 - 0.225 * cos(2 * pi * _eased.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              color: _colorAt(_eased.value).withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          );
        },
      ),
    );
  }
}

/// The app's one indeterminate loading state.
///
/// An instrument reading, not a spinner: a single element breathing through
/// Indigo, Pink, and the thermal corona. Anywhere this appears, a
/// `CircularProgressIndicator` used to.
class PulseIndicator extends StatelessWidget {
  /// The size of the breathing element itself.
  final double size;

  /// Centres the indicator in the space it is given. A loading state that owns
  /// its whole surface wants this; one sitting inside a row does not.
  final bool centered;

  /// Optional line beneath the indicator, for waits long enough that the user
  /// deserves to know what is being waited on.
  final String? label;

  const PulseIndicator({
    super.key,
    this.size = 28,
    this.centered = true,
    this.label,
  });

  /// The palette every loading state in the app breathes through. Read from
  /// the theme so a surface pinned to one appearance stays coherent.
  static List<Color> paletteOf(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return <Color>[scheme.primary, scheme.secondary, MapPalette.thermalCorona];
  }

  @override
  Widget build(BuildContext context) {
    final Widget pulse = SizedBox(
      width: size,
      height: size,
      child: ChromaticPulse(colors: paletteOf(context)),
    );

    Widget content = pulse;
    if (label != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          pulse,
          const SizedBox(height: MapSpacing.sm),
          Text(
            label!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    }

    // One node, announced once. Without `container` the label has no node of
    // its own to live on, and without excluding the subtree the visible label
    // is read a second time straight after it.
    content = Semantics(
      container: true,
      liveRegion: true,
      label: label ?? 'Loading',
      child: ExcludeSemantics(child: content),
    );

    return centered ? Center(child: content) : content;
  }
}
