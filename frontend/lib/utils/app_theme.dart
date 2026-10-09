import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'a11y_constants.dart';

/// Named accent colors for map overlays. See DESIGN.md §2.
///
/// These category accents (airport, station types) live deliberately outside
/// the natural OSM tile palette so map-overlay UI reads as distinct from
/// terrain, per the Outside-the-Tile-Palette Rule.
class MapPalette {
  const MapPalette._();

  static const Color airport = Color(0xFF1565C0);
  static const Color majorStation = Color(0xFFE65100);
  static const Color commuterRail = Color(0xFF00695C);
  static const Color subway = Color(0xFF2E7D32);
  static const Color regionalStation = Color(0xFF607D8B);

  // Compass north arrow. Red is the universally-read north convention;
  // tokenized here as a deliberate Evening Palette exception, not a leak.
  static const Color compassNorth = Color(0xFFC62828);

  // Default home-pin fallback when a profile has no custom pin color set.
  // Evening Indigo from the brand palette.
  static const Color defaultPin = Color(0xFF3F51B5);

  /// The brand's secondary. Named here because it was being written out as a
  /// literal at every call site that wanted it.
  static const Color accent = Color(0xFFFF4081);

  // Thermal energy tokens
  static const Color thermalCore = Color(0xFFFF3B30);
  static const Color thermalCorona = Color(0xFFFF9500);

  /// The connection spectrum, warmest where a connection has waited longest.
  ///
  /// These were literals in three files, which is what makes DESIGN.md's Rare
  /// Accent Rule ("high-chroma accents occupy <=10% of any screen") impossible
  /// to hold: a rule about how much colour a surface carries can only be kept
  /// if the colours are countable in one place.
  static const MapSignal vital = MapSignal(
    Color(0xFF14B8A6),
    Color(0xFF00695C),
    Color(0xFF5EEAD4),
  );
  static const MapSignal calm = MapSignal(
    Color(0xFF6B7280),
    Color(0xFF4B5563),
    Color(0xFF9CA3AF),
  );
  static const MapSignal due = MapSignal(
    thermalCorona,
    Color(0xFFB45309),
    Color(0xFFFCD34D),
  );
  static const MapSignal overdue = MapSignal(
    Color(0xFFFF5A1F),
    Color(0xFFC2410C),
    Color(0xFFFB923C),
  );
  static const MapSignal critical = MapSignal(
    thermalCore,
    Color(0xFFB91C1C),
    Color(0xFFF87171),
  );

  /// Trip status. Kept off the connection spectrum on purpose -- a cancelled
  /// trip is not an overdue friendship, and reusing one spectrum for both
  /// would make the app's warmest colour mean two different things.
  static const MapSignal journeyConfirmed = MapSignal(
    Color(0xFF2E7D32),
    Color(0xFF2E7D32),
    Color(0xFF81C784),
  );
  static const MapSignal journeyCancelled = MapSignal(
    Color(0xFFC62828),
    Color(0xFFC62828),
    Color(0xFFE57373),
  );
  static const MapSignal journeyPlanned = MapSignal(
    Color(0xFFEF6C00),
    Color(0xFFEF6C00),
    Color(0xFFFFB74D),
  );
}

/// A colour that carries meaning, in the two strengths a meaning needs.
///
/// [vivid] is the saturated tone for a mark — an orb, a dot, a rule, a glow.
/// [ink] is the same meaning at text contrast, which is a different colour in
/// each appearance because 4.5:1 against the void and against daylight are not
/// the same problem. Pairing them here is what stops a call site from reaching
/// for the vivid tone as a text colour, which is the usual way an accent
/// becomes an accessibility bug.
class MapSignal {
  final Color vivid;
  final Color _inkLight;
  final Color _inkDark;

  const MapSignal(this.vivid, this._inkLight, this._inkDark);

  Color ink(Brightness brightness) =>
      brightness == Brightness.dark ? _inkDark : _inkLight;
}

/// Refractive Glass material constants. See DESIGN.md §4–5 and the LLC
/// `refractive-glass.md` Tier 3 template.
///
/// The tint band is the load-bearing part. Below [tintMin] the surface stops
/// separating from what it floats over; above [tintMax] it stops reading as
/// glass and starts reading as a tinted card — the flat-UI register PRODUCT.md
/// lists as an anti-reference. Dark mode is where that ceiling matters most,
/// because DESIGN.md §6 asks for "pristine glass in a void", not dark blue
/// software.
///
/// Legibility in dark mode is therefore bought at the *edge*, not in the fill:
/// [edgeDark] carries more than [edgeLight] precisely because [tintDark] is
/// only marginally higher than [tintLight].
class MapGlass {
  const MapGlass._();

  /// Backdrop blur sigma. The LLC standard refractive look.
  static const double blurSigma = 20.0;

  /// Fill opacity band for the Tier 3 material. The *composed* value —
  /// base tint plus [sheen] — is what must stay inside it.
  static const double tintMin = 0.05;
  static const double tintMax = 0.15;

  /// Top-left lift that gives the surface a direction of light.
  static const double sheen = 0.03;

  /// Base fill per appearance.
  ///
  /// Light sits lower than dark on purpose. The light body is a dark neutral
  /// over a pale ground, so every point of alpha buys much more contrast than
  /// it does in the void — at 0.10 the panel stopped reading as a lens and
  /// started reading as a grey slab laid on the field.
  static const double tintLight = 0.08;
  static const double tintDark = 0.12;

  /// The precision edge (DESIGN.md §5).
  static const double edgeLight = 0.20;
  static const double edgeDark = 0.28;
  static const double edgeWidth = 0.5;

  /// An **inlay**: a surface in the glass family that cannot afford a backdrop
  /// sample.
  ///
  /// The GPU budget is per screen, not per widget — a form with nine fields
  /// cannot spend nine `BackdropFilter` layers on them. An inlay is the same
  /// material with the blur removed: the fill and the precision edge, nothing
  /// else. It is what a chip, an avatar well, a field, or a list row is made
  /// of, and it is why replacing Material's tonal roles everywhere costs no
  /// frames. A floating panel is glass; something set *into* a panel is inlay.
  static Color inlayFill(Brightness brightness) => brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.07)
      : bodyLight.withValues(alpha: 0.05);

  /// A deeper inlay, for a well that something else sits inside — an avatar
  /// backing, a swatch, a selected segment.
  static Color inlayFillStrong(Brightness brightness) =>
      brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.13)
      : bodyLight.withValues(alpha: 0.10);

  /// The inlay's edge. Lighter than [edgeLight]/[edgeDark]: an inlay sits
  /// inside a surface rather than floating above one, so it needs to separate,
  /// not to catch the light.
  static Color inlayEdge(Brightness brightness) => brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.14)
      : bodyLight.withValues(alpha: 0.12);

  /// The body of the material in the light appearance.
  ///
  /// A lens is only visible when it differs from what it floats over. Over the
  /// [MapField] light ground the old white-on-white fill and white edge were
  /// invisible — the panel existed in the widget tree and nowhere on screen.
  /// Light glass is therefore the same void neutral the dark appearance is
  /// made *of*, laid over daylight at low alpha: one material, two rooms.
  static const Color bodyLight = Color(0xFF0F1020);

  /// Radii on the DESIGN.md scale: sm 8 / md 16 / lg 30.
  static const double radiusSm = 8.0;
  static const double radiusMd = 16.0;
  static const double radiusLg = 30.0;

  /// A fully rounded end, for small status chips only.
  ///
  /// Named so it reads as the one deliberate exception to the scale rather
  /// than as a magic number. A pill is for a chip; a panel or an action that
  /// reaches for this shape has mistaken a label for a surface.
  static const double radiusPill = 999.0;

  /// Selection inside glass chrome (DESIGN.md §5, Navigation): a background
  /// lift, never a solid colour fill. Dark carries more because a white lift
  /// on a dark pane reads weaker than a black lift on a light one.
  static const double selectionLiftDark = 0.15;
  static const double selectionLiftLight = 0.08;

  /// The selection lift resolved for [brightness].
  static Color selectionLift(Brightness brightness) {
    return brightness == Brightness.dark
        ? Colors.white.withValues(alpha: selectionLiftDark)
        : Colors.black.withValues(alpha: selectionLiftLight);
  }
}

/// The Ambient Field — the layer every glass surface refracts.
///
/// `GlassContainer` blurs what sits *behind* it, so a flat scaffold colour
/// makes the material disappear: blurring one colour returns that colour. Every
/// surface outside the Map therefore floats over this field instead, and the
/// Map floats over live tiles, which is the same contract by other means.
///
/// Four soft masses drift on independent closed orbits. Closed is the load-
/// bearing word — each mass completes a whole number of cycles per [cycle], so
/// the composition is continuous when the controller wraps and never jumps.
class MapField {
  const MapField._();

  /// One full composition cycle. Long enough that the field never appears to
  /// be *playing*; it is weather, not animation.
  static const Duration cycle = Duration(seconds: 120);

  /// The drift is resampled this many times per cycle — about 30fps at
  /// [cycle]'s length. Past this the masses move well under a pixel per frame,
  /// so the extra repaints buy nothing and cost a full-screen re-blur of every
  /// glass surface above the field.
  static const int driftSteps = 3600;

  /// Where the composition rests when motion is disabled. Chosen for the
  /// still, not inherited from frame zero.
  static const double stillPhase = 0.18;

  /// The void (DESIGN.md §6): near-neutral, so the only chroma in the field
  /// comes from the masses. A blue-grey ground here is how it becomes "dark
  /// blue software".
  static const List<Color> groundDark = <Color>[
    Color(0xFF08080B),
    Color(0xFF101018),
    Color(0xFF08080B),
  ];

  /// Luminous daylight: the same composition in a lit room.
  static const List<Color> groundLight = <Color>[
    Color(0xFFF7F8FB),
    Color(0xFFEDEFF5),
    Color(0xFFF7F8FB),
  ];

  /// The ground colour a surface should assume when it needs one flat value —
  /// a first frame, a high-contrast fallback, a platform window background.
  static Color ground(Brightness brightness) =>
      brightness == Brightness.dark ? groundDark[1] : groundLight[1];

  static const List<FieldMass> masses = <FieldMass>[
    // Indigo, the brand's structural colour, carries the largest mass.
    FieldMass(
      color: Color(0xFF3F51B5),
      alphaDark: 0.22,
      alphaLight: 0.16,
      radiusFactor: 0.62,
      center: Offset(0.28, 0.24),
      amplitude: Offset(0.16, 0.13),
      cyclesX: 1,
      cyclesY: 2,
      phaseX: 0.0,
      phaseY: 0.35,
    ),
    FieldMass(
      color: Color(0xFFFF4081),
      alphaDark: 0.16,
      alphaLight: 0.11,
      radiusFactor: 0.48,
      center: Offset(0.78, 0.68),
      amplitude: Offset(0.14, 0.17),
      cyclesX: 2,
      cyclesY: 1,
      phaseX: 0.52,
      phaseY: 0.11,
    ),
    FieldMass(
      color: Color(0xFF3F51B5),
      alphaDark: 0.14,
      alphaLight: 0.10,
      radiusFactor: 0.54,
      center: Offset(0.62, 0.18),
      amplitude: Offset(0.19, 0.11),
      cyclesX: 3,
      cyclesY: 2,
      phaseX: 0.27,
      phaseY: 0.74,
    ),
    // Thermal corona, kept lowest: a trace of heat in the room, never a source.
    FieldMass(
      color: Color(0xFFFF9500),
      alphaDark: 0.10,
      alphaLight: 0.07,
      radiusFactor: 0.44,
      center: Offset(0.18, 0.82),
      amplitude: Offset(0.13, 0.12),
      cyclesX: 2,
      cyclesY: 3,
      phaseX: 0.66,
      phaseY: 0.42,
    ),
  ];
}

/// One drifting luminous mass in the [MapField].
///
/// Position is a Lissajous figure rather than a circle: two independent whole-
/// number frequencies per axis trace a path that reads as unrepeating at human
/// timescales while still closing exactly at the end of the cycle.
class FieldMass {
  final Color color;

  /// Peak alpha at the centre of the mass, per appearance.
  final double alphaDark;
  final double alphaLight;

  /// Radius as a fraction of the surface's longest side.
  final double radiusFactor;

  /// Orbit centre and half-extent, both as fractions of the surface.
  final Offset center;
  final Offset amplitude;

  /// Whole cycles per [MapField.cycle] on each axis. Integers keep the orbit
  /// closed; a fractional value would snap the mass back on every wrap.
  final int cyclesX;
  final int cyclesY;

  /// Starting offset into each axis, in turns.
  final double phaseX;
  final double phaseY;

  const FieldMass({
    required this.color,
    required this.alphaDark,
    required this.alphaLight,
    required this.radiusFactor,
    required this.center,
    required this.amplitude,
    required this.cyclesX,
    required this.cyclesY,
    required this.phaseX,
    required this.phaseY,
  });

  double alpha(Brightness brightness) =>
      brightness == Brightness.dark ? alphaDark : alphaLight;
}

/// LLC Interaction Physics — the constants in
/// `llc-standards/context/interaction-physics.md`, and the two-phase Thermal
/// Glow they drive.
///
/// The spec asks for three things that only fit together once you notice they
/// describe different parts of one gesture: a 50ms excitation, a 300ms
/// dissipation, and a spring for "all state returns" (DESIGN.md §6). The
/// spring is not the glow. Energy blooms and cools on a curve; the *surface*
/// is what yields under the touch and springs back.
class MapMotion {
  const MapMotion._();

  /// Phase 1 — the strike. Intent converts to energy.
  static const Duration excitation = Duration(milliseconds: 50);

  /// Phase 2 — the cooling cycle.
  static const Duration dissipation = Duration(milliseconds: 300);

  /// `interaction-physics.md` §Animation Curvature: velocity highest at the
  /// start, trailing off. Quart.out or Quint.out, and nothing else — the
  /// component previously used easeOutExpo, which is neither.
  static const Curve strike = Curves.easeOutQuart;

  static const double springMass = 1.0;
  static const double springStiffness = 180.0;
  static const double springDamping = 12.0;

  /// The return to neutral. Damping 12 against stiffness 180 sits at a ratio
  /// of ~0.45 — underdamped on purpose, so the surface arrives with one
  /// slight overshoot rather than easing to a stop. That overshoot is the
  /// "sharp, authoritative return" the spec asks for; a critically damped
  /// spring would read as soft.
  static const SpringDescription returnSpring = SpringDescription(
    mass: springMass,
    stiffness: springStiffness,
    damping: springDamping,
  );

  /// Chromatic Pulse — the loading loop, and a deliberately separate motion
  /// category from everything above.
  ///
  /// `chromatic-pulse.md` is explicit that this is a continuous idle-state loop
  /// with no user input, so it uses a *symmetric* ease-in-out rather than the
  /// brand's asymmetric slow-in/snap-out interaction curve, and must not reuse
  /// the spring constants. Slow on purpose: it can run for the whole length of
  /// a bad connection and must not feel frantic while it does.
  static const Duration chromaticCycle = Duration(milliseconds: 3200);
  static const Curve chromatic = Cubic(0.45, 0.0, 0.55, 1.0);

  /// How far a surface yields under contact, as a fraction of its size.
  ///
  /// Small on purpose: these wrap 44pt controls and map pills, and PRODUCT.md
  /// asks for a precision instrument, not a toy. At 4% a 44pt control moves
  /// under two logical pixels — felt more than seen, which is the point.
  static const double pressDepth = 0.04;
}

/// The DESIGN.md spacing scale.
///
/// Layout reads as intentional when gaps come from a scale rather than from
/// whatever number looked right in the moment. Tight groups take [xs]–[sm];
/// distinct groups take [md]–[lg].
class MapSpacing {
  const MapSpacing._();

  static const double xs = 8.0;
  static const double sm = 16.0;
  static const double md = 24.0;
  static const double lg = 32.0;

  /// Interior padding for a full-surface glass panel — an empty state, a
  /// dialog body. Deliberately above [lg]: these panels earn their calm from
  /// the air around their content.
  static const double panel = 40.0;
}

class AppTheme {
  // Brand Colors
  static const Color _brandColor = Color(0xFF3F51B5);
  static const Color _secondaryColor = Color(0xFFFF4081);

  /// How the type scale is built.
  ///
  /// Swappable because creating a GoogleFonts `TextStyle` starts a network
  /// fetch the instant it is constructed — not when it is first painted — so
  /// merely touching this class in an offline widget test raises an async
  /// failure with no stable place to catch it. Tests point this at a local
  /// face; production never reassigns it.
  @visibleForTesting
  static TextTheme Function(Color color) textThemeBuilder = buildBrandTextTheme;

  /// Drops the memoised themes so a changed [textThemeBuilder] takes effect.
  @visibleForTesting
  static void resetThemeCache() {
    _lightTheme = null;
    _darkTheme = null;
  }

  static ThemeData? _lightTheme;
  static ThemeData? _darkTheme;

  static ThemeData get lightTheme => _lightTheme ??= _buildLightTheme();
  static ThemeData get darkTheme => _darkTheme ??= _buildDarkTheme();

  /// The brand scale: Montserrat for structure, Open Sans for reading.
  static TextTheme buildBrandTextTheme(Color color) {
    return TextTheme(
      displayLarge: GoogleFonts.montserrat(
        fontSize: 57,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.25,
        height: 1.1,
      ),
      displayMedium: GoogleFonts.montserrat(
        fontSize: 45,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      displaySmall: GoogleFonts.montserrat(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      headlineLarge: GoogleFonts.montserrat(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      headlineMedium: GoogleFonts.montserrat(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      headlineSmall: GoogleFonts.montserrat(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleLarge: GoogleFonts.montserrat(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      titleMedium: GoogleFonts.openSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.15,
      ),
      titleSmall: GoogleFonts.openSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.1,
      ),
      bodyLarge: GoogleFonts.openSans(
        fontSize: 16,
        fontWeight: FontWeight.w300,
        color: color,
        letterSpacing: 0.5,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.openSans(
        fontSize: 14,
        fontWeight: FontWeight.w300,
        color: color,
        letterSpacing: 0.25,
      ),
      bodySmall: GoogleFonts.openSans(
        fontSize: 12,
        fontWeight: FontWeight.w300,
        color: color,
        letterSpacing: 0.4,
      ),
      labelLarge: GoogleFonts.montserrat(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.5,
      ),
    );
  }

  // Light Theme
  static ThemeData _buildLightTheme() => ThemeData(
    useMaterial3: true,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: _brandColor,
          brightness: Brightness.light,
          secondary: _secondaryColor,
        ).copyWith(
          onSurface: Colors.black87,
          onPrimaryContainer: Colors.indigo.shade900,
          onSecondaryContainer: const Color(0xFF4D002B), // High contrast pink
        ),
    textTheme: textThemeBuilder(Colors.black87),
    iconTheme: const IconThemeData(color: Colors.black87, size: 24),
    // The flat ground of the Ambient Field. Screens that float over the field
    // set `backgroundColor: Colors.transparent`; this is what a surface that
    // forgets to degrades into — the field's average, not a foreign grey.
    scaffoldBackgroundColor: MapField.groundLight[1],
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: _brandColor,
      // Derived, not restated. A raw TextStyle here silently dropped
      // Montserrat — the same drift the empty states had — and set a size the
      // dark theme did not share. Dark inherits titleLarge; light now uses the
      // same style in the brand colour, so the two appearances agree.
      titleTextStyle: textThemeBuilder(_brandColor).titleLarge,
    ),
    // Material's expanding ink circle is the most recognisable thing about
    // Material, and it is a different interaction language from Thermal Glow:
    // a ripple travels *from* the touch point in the theme's primary, while
    // this system's surfaces take on heat and yield under the finger. Removing
    // the splash leaves the state overlay, which is retinted below so a press
    // reads as the surface warming rather than as a wave crossing it.
    splashFactory: NoSplash.splashFactory,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        // Flat by default. DESIGN.md §4 resolves depth by refraction and §6
        // bans drop shadows outright; a raised button is the Material default
        // leaking through, not a decision this system made.
        elevation: 0,
        // And an action, not a tonal surface: Material's default fill is a
        // near-white in light and a near-black in dark, both of which vanish
        // against the Ambient Field.
        backgroundColor: _brandColor,
        foregroundColor: Colors.white,
        overlayColor: MapPalette.thermalCore,
        padding: const EdgeInsets.symmetric(
          horizontal: MapSpacing.md,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        elevation: 0,
        overlayColor: MapPalette.thermalCore,
        padding: const EdgeInsets.symmetric(
          horizontal: MapSpacing.md,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        overlayColor: MapPalette.thermalCore,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        overlayColor: MapPalette.thermalCore,
        // Material's default here is a stadium, which is off the 8/16/30 scale
        // entirely. Pills are for small status chips, not for actions.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        overlayColor: MapPalette.thermalCore,
      ),
    ),
    // A field is an inlay: the glass material minus the backdrop sample, so a
    // form of nine inputs costs no blur passes. An opaque white fill here read
    // as a sticker laid on the Ambient Field rather than a well cut into it.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MapGlass.inlayFill(Brightness.light),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        borderSide: BorderSide(color: MapGlass.inlayEdge(Brightness.light)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        borderSide: BorderSide(color: MapGlass.inlayEdge(Brightness.light)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        borderSide: BorderSide(color: _brandColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MapSpacing.sm,
        vertical: MapSpacing.sm,
      ),
    ),
    cardTheme: CardThemeData(
      // Depth is declared once, and as an edge — never a shadow (DESIGN.md
      // §4). A card is not glass, so it earns its separation from a hairline
      // outline rather than from refraction.
      elevation: 0,
      color: MapGlass.inlayFill(Brightness.light),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MapGlass.radiusMd),
        side: BorderSide(color: MapGlass.inlayEdge(Brightness.light)),
      ),
      margin: const EdgeInsets.symmetric(
        vertical: MapSpacing.xs,
        horizontal: MapSpacing.sm,
      ),
    ),
  );

  // Dark Theme
  static ThemeData _buildDarkTheme() => ThemeData(
    useMaterial3: true,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: _brandColor,
          brightness: Brightness.dark,
          secondary: _secondaryColor,
        ).copyWith(
          onSurface: Colors.white,
          onPrimaryContainer: const Color(0xFFE8EAF6), // Indigo 50
          onSecondaryContainer: const Color(0xFFFFE1F0), // Pink 50
        ),
    textTheme: textThemeBuilder(Colors.white),
    iconTheme: const IconThemeData(color: Colors.white, size: 24),
    scaffoldBackgroundColor: MapField.groundDark[1],
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
    ),
    // Material's expanding ink circle is the most recognisable thing about
    // Material, and it is a different interaction language from Thermal Glow:
    // a ripple travels *from* the touch point in the theme's primary, while
    // this system's surfaces take on heat and yield under the finger. Removing
    // the splash leaves the state overlay, which is retinted below so a press
    // reads as the surface warming rather than as a wave crossing it.
    splashFactory: NoSplash.splashFactory,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        // Flat by default. DESIGN.md §4 resolves depth by refraction and §6
        // bans drop shadows outright; a raised button is the Material default
        // leaking through, not a decision this system made.
        elevation: 0,
        // And an action, not a tonal surface: Material's default fill is a
        // near-white in light and a near-black in dark, both of which vanish
        // against the Ambient Field.
        backgroundColor: _brandColor,
        foregroundColor: Colors.white,
        overlayColor: MapPalette.thermalCore,
        padding: const EdgeInsets.symmetric(
          horizontal: MapSpacing.md,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        elevation: 0,
        overlayColor: MapPalette.thermalCore,
        padding: const EdgeInsets.symmetric(
          horizontal: MapSpacing.md,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        overlayColor: MapPalette.thermalCore,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        overlayColor: MapPalette.thermalCore,
        // Material's default here is a stadium, which is off the 8/16/30 scale
        // entirely. Pills are for small status chips, not for actions.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: A11yConstants.minTouchSize,
        overlayColor: MapPalette.thermalCore,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MapGlass.inlayFill(Brightness.dark),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        borderSide: BorderSide(color: MapGlass.inlayEdge(Brightness.dark)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        borderSide: BorderSide(color: MapGlass.inlayEdge(Brightness.dark)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MapGlass.radiusSm),
        borderSide: BorderSide(color: _brandColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MapSpacing.sm,
        vertical: MapSpacing.sm,
      ),
    ),
    cardTheme: CardThemeData(
      // Depth is declared once, and as an edge — never a shadow (DESIGN.md
      // §4). A card is not glass, so it earns its separation from a hairline
      // outline rather than from refraction.
      elevation: 0,
      color: MapGlass.inlayFill(Brightness.dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MapGlass.radiusMd),
        side: BorderSide(color: MapGlass.inlayEdge(Brightness.dark)),
      ),
      margin: const EdgeInsets.symmetric(
        vertical: MapSpacing.xs,
        horizontal: MapSpacing.sm,
      ),
    ),
  );
}
