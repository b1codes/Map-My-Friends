import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../utils/app_theme.dart';

/// The machine coming alive under the user's touch.
///
/// One gesture, two materials. Energy transfers from the finger into the
/// surface as a Thermal Glow — a 50ms strike, then a 300ms cooling cycle. The
/// surface itself has mass: it yields under the contact and springs back to
/// neutral when released, at the stiffness and damping
/// `llc-standards/context/interaction-physics.md` calibrates for
/// high-precision hardware.
///
/// Keeping those on separate clocks is the whole design. The glow is thermal
/// and belongs on a decelerating curve; the displacement is mechanical and
/// belongs on a spring. Driving both from one controller would force the glow
/// to oscillate with the surface, which reads as a flicker rather than as heat.
class ThermalResponse extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;

  /// Whether the surface answers a touch at all.
  ///
  /// Distinct from a null [onTap], which many call sites use while handling the
  /// gesture themselves further up. A disabled control still occupies the
  /// screen, and glowing under a finger that cannot act is the interface
  /// lying about what it will do.
  final bool enabled;

  const ThermalResponse({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = MapGlass.radiusSm,
    this.enabled = true,
  });

  @override
  State<ThermalResponse> createState() => _ThermalResponseState();
}

class _ThermalResponseState extends State<ThermalResponse>
    with TickerProviderStateMixin {
  /// Heat: 0 at rest, 1 at full excitation.
  late final AnimationController _heat;
  late final Animation<double> _glow;

  /// Displacement: 0 at rest, 1 fully depressed. Unbounded because the return
  /// spring overshoots past neutral, and a clamped controller would flatten
  /// exactly the overshoot that makes the return read as authoritative.
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();

    _heat = AnimationController(
      vsync: this,
      duration: MapMotion.dissipation,
      reverseDuration: MapMotion.dissipation,
    );
    _glow = CurvedAnimation(
      parent: _heat,
      curve: MapMotion.strike,
      reverseCurve: MapMotion.strike,
    );

    _press = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _heat.dispose();
    _press.dispose();
    super.dispose();
  }

  /// Spatial movement is what reduced-motion settings are about. The glow is
  /// colour and luminosity, not displacement, and it is the part that confirms
  /// the tap landed — so it survives while the yield does not.
  bool get _allowsDisplacement => !MediaQuery.disableAnimationsOf(context);

  void _strike() {
    _heat.animateTo(1.0, duration: MapMotion.excitation);
    if (_allowsDisplacement) {
      _press.animateTo(
        1.0,
        duration: MapMotion.excitation,
        curve: MapMotion.strike,
      );
    }
  }

  void _release() {
    _heat.reverse();
    if (!_allowsDisplacement) {
      _press.value = 0.0;
      return;
    }
    // Carry the current velocity into the simulation so an interrupted press
    // continues from the motion already underway rather than restarting.
    _press.animateWith(
      SpringSimulation(
        MapMotion.returnSpring,
        _press.value,
        0.0,
        _press.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedBuilder(
      animation: Listenable.merge([_glow, _press]),
      // The wrapped subtree is passed through rather than rebuilt: only the
      // glow's decoration and the surface's transform change per frame.
      child: widget.child,
      builder: (context, child) {
        final heat = _glow.value;
        final scale = 1.0 - _press.value * MapMotion.pressDepth;

        return Transform.scale(
          scale: scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (heat > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: MapPalette.thermalCore.withValues(
                              alpha: 0.5 * heat,
                            ),
                            blurRadius: 20 * heat,
                            spreadRadius: 5 * heat,
                          ),
                          BoxShadow(
                            color: MapPalette.thermalCorona.withValues(
                              alpha: 0.3 * heat,
                            ),
                            blurRadius: 40 * heat,
                            spreadRadius: 10 * heat,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              child!,
            ],
          ),
        );
      },
    );

    if (!widget.enabled) return content;

    if (widget.onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: content,
      );
    }

    return Listener(
      onPointerDown: (_) => _strike(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      behavior: HitTestBehavior.translucent,
      child: content,
    );
  }
}
