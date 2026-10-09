---
version: 1
slug: "frontend-lib-main-dart"
primary_target: "frontend/lib/main.dart"
related_targets: ["frontend/lib/components/shared/ambient_field.dart","frontend/lib/screens/people/people_screen.dart","frontend/lib/screens/pulse/pulse_screen.dart","frontend/lib/screens/profile/me_screen.dart","frontend/lib/screens/trips/trips_screen.dart","frontend/lib/screens/settings/settings_screen.dart"]
---

# Surface brief: The Ambient Field

## Job and audience
Every non-map surface of Map My Friends — People, Pulse, Trips, Me, Settings, auth, and every
sheet and dialog that floats over them. The visitor is mid-task (Operate mode): finding a person,
logging a touchpoint, editing a trip. They are not here to admire the interface; they are here to
finish something and should feel the instrument's quality while doing it.

## The problem this solves
`GlassContainer` blurs what sits behind it. Outside the Map tab there is nothing behind it —
`scaffoldBackgroundColor: Colors.grey[50]` in light, M3 `surface` in dark. Blurring a flat colour
returns that same flat colour, so the material degrades to a translucent card and Material 3's
tonal-elevation roles were adopted (43 sites) to do the depth work glass could not. The glass nav
bar in `main.dart` refracts nothing on four of five tabs.

## Selected direction — Orbital Drift
A single ambient layer beneath every screen, above nothing, owned by the shell.

- **Structure**: four large, very soft radial masses on independent elliptical orbits over a deep
  ground. Indigo `#3F51B5` and Pink `#FF4081` from the brand palette, plus one Thermal Corona
  `#FF9500` mass at the lowest opacity of the set so the field carries a trace of heat.
- **Why it works**: refraction only reads when the thing behind the lens has luminance structure
  that *moves* relative to the panel edge. Drifting light is the cheapest source of that structure
  and the one that makes a static panel feel alive when the user scrolls past it.
- **Motion**: 60–90s per orbit, independent periods so the composition never visibly repeats. This
  is ambient, not animation — no element should ever appear to be "playing". Fully suspended under
  `MediaQuery.disableAnimations`, which freezes the field at a composed still rather than removing it.
- **Dark ("the void")**: ground `#08080B` → `#101018`, masses at 0.10–0.22 alpha. DESIGN.md §6 asks
  for "pristine glass in a void", not dark blue software: the ground is near-neutral and the only
  chroma in the field comes from the masses themselves.
- **Light ("luminous daylight")**: the same field inverted — a pale cool-white ground
  `#F7F8FB` → `#EDEFF5` with the same masses at 0.10–0.16, and glass tinting *darker* than its
  backdrop instead of lighter. Both appearances are first-class; the theme switcher stays honest.

## Implementation consequence
- One `AmbientField` widget, one `CustomPainter`, one `AnimationController` in the shell, inside a
  `RepaintBoundary` so the drift never repaints the screen above it.
- Painted with `MaskFilter.blur` on radial-gradient circles — no image assets, no fragment shader,
  no new dependency. Keeps the app at LLC Tier 3 across all six platforms.
- Every screen `Scaffold` becomes `backgroundColor: Colors.transparent`. The existing
  `BackdropGroup` in `main.dart` then gives the whole shell one shared backdrop sample.
- The field is *behind* the backdrop group, so it costs no extra `BackdropFilter` layer.

## Scope and boundaries
- The Map tab keeps live tiles as its backdrop; the field is not drawn there.
- Content, copy, data, navigation structure, and BLoC wiring are untouched.
- **Anti-goals**: the field must never compete with content, never animate fast enough to notice
  directly, never tint text, and never become a "hero moment" — it is atmosphere, not a feature.
  No decorative particles, no starfield, no parallax on gesture.

## States and ranges
Renders identically under: empty states, loading, error, keyboard-open, 0.85×–2.0× text scale, all
six platforms, phone through desktop, both appearances, and reduced-motion.

## Accessibility contract
- `MediaQuery.highContrast` collapses the field to a flat token colour and `GlassContainer`'s
  existing opaque path takes over; no legibility depends on the field.
- Reduced motion freezes the drift; the composition remains.
- The field is decorative: `ExcludeSemantics`, never focusable, never announced.
