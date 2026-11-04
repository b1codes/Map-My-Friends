/// Accessibility problems the catalog checks know about and have a task for.
///
/// Each entry is a catalog path (with the variant, for contrast) and how
/// many problems that check finds there today. The checks fail on any
/// other number, so fixing a problem means lowering its count here, and
/// a new problem can't hide behind an old one. When an entry reaches zero,
/// delete it.
library;

/// A count of problems on one entry, and the task that will fix them.
class KnownGap {
  const KnownGap(this.issues, this.task);

  final int issues;
  final String task;
}

const _thisBranch = 'the accessibility subtask (ClickUp 86bcqv0gb)';
const _smallTapTargets = 'the small tap targets task (to be filed)';
const _lowContrast = 'the low text contrast task (to be filed)';
const _largeText = 'the 200% text overflow task (to be filed)';

/// Tap targets smaller than 48x48 (A11yConstants.minTouchTargetSize).
const tapTargetGaps = <String, KnownGap>{
  'components/map/mapsettingsbutton/over-the-map-(tap-to-open)': KnownGap(
    1,
    _smallTapTargets,
  ),
  'components/map/mapsettingsmodal/inline': KnownGap(1, _smallTapTargets),
  'components/map/personmapmarker/sample-people-(tap-one)': KnownGap(
    5,
    _smallTapTargets,
  ),
  'components/pulse/logcontactsheet/inline': KnownGap(3, _smallTapTargets),
  'components/pulse/pulsecalendar/interactive': KnownGap(4, _smallTapTargets),
  'screens/map/mapscreen/default': KnownGap(4, _smallTapTargets),
  'screens/profile/mescreen/states': KnownGap(1, _smallTapTargets),
  'screens/shell/mainscreen/navigation-chrome': KnownGap(4, _smallTapTargets),
  'screens/trips/tripdetailsscreen/default': KnownGap(1, _smallTapTargets),
};

/// Tappable nodes a screen reader has no name for.
const labelGaps = <String, KnownGap>{
  'components/map/horizontaltripplanner/planning-a-trip': KnownGap(
    1,
    _thisBranch,
  ),
  'components/map/mapcontrols/over-the-map': KnownGap(1, _thisBranch),
  'components/map/mapsettingsbutton/over-the-map-(tap-to-open)': KnownGap(
    2,
    _thisBranch,
  ),
  'components/pulse/logcontactsheet/inline': KnownGap(1, _thisBranch),
  'screens/map/mapscreen/default': KnownGap(2, _thisBranch),
  'screens/people/addeditpersonscreen/add': KnownGap(1, _thisBranch),
  'screens/people/addeditpersonscreen/edit': KnownGap(1, _thisBranch),
  'screens/profile/mescreen/states': KnownGap(1, _thisBranch),
  'screens/shell/mainscreen/navigation-chrome': KnownGap(2, _thisBranch),
  'screens/trips/tripdetailsscreen/default': KnownGap(1, _thisBranch),
};

/// Layout overflows with the system text size at 200%.
const largeTextGaps = <String, KnownGap>{
  'components/map/unifiedclustermodal/cluster-contents': KnownGap(
    1,
    _largeText,
  ),
  'components/people/personcard/grid': KnownGap(12, _largeText),
  'components/pulse/contactrostertile/default': KnownGap(1, _largeText),
  'components/pulse/contactrostertile/every-recency-level': KnownGap(
    6,
    _largeText,
  ),
  'components/shared/glassdialog/playground': KnownGap(1, _largeText),
  'screens/auth/loginscreen/default': KnownGap(3, _largeText),
};

/// Text below WCAG AA contrast: 4.5:1, or 3:1 for large text.
const contrastGaps = <String, KnownGap>{
  'components/map/airportbottomsheet/default (dark)': KnownGap(2, _lowContrast),
  'components/map/airportbottomsheet/default (dark, high contrast)': KnownGap(
    2,
    _lowContrast,
  ),
  'components/map/airportbottomsheet/default (light)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/map/airportbottomsheet/default (light, high contrast)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/map/basebottomsheet/playground (dark)': KnownGap(2, _lowContrast),
  'components/map/basebottomsheet/playground (dark, high contrast)': KnownGap(
    2,
    _lowContrast,
  ),
  'components/map/basebottomsheet/playground (light)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/map/basebottomsheet/playground (light, high contrast)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/map/horizontaltripplanner/planning-a-trip (dark)': KnownGap(
    1,
    _thisBranch,
  ),
  'components/map/horizontaltripplanner/planning-a-trip (dark, high contrast)':
      KnownGap(1, _thisBranch),
  'components/map/stationbottomsheet/default (dark)': KnownGap(1, _lowContrast),
  'components/map/stationbottomsheet/default (dark, high contrast)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/map/stationbottomsheet/default (light)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/map/stationbottomsheet/default (light, high contrast)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/pulse/logcontactsheet/inline (light)': KnownGap(2, _lowContrast),
  'components/pulse/logcontactsheet/inline (light, high contrast)': KnownGap(
    2,
    _lowContrast,
  ),
  'components/shared/customtextformfield/validation-error (light)': KnownGap(
    2,
    _lowContrast,
  ),
  'components/shared/customtextformfield/validation-error (light, high contrast)':
      KnownGap(2, _lowContrast),
  'components/shared/glasscontainer/isolated-(over-other-glass) (dark)':
      KnownGap(1, _thisBranch),
  'components/shared/glasscontainer/isolated-(over-other-glass) (dark, high contrast)':
      KnownGap(1, _thisBranch),
  'components/shared/glassdialog/confirm-(tap-to-open) (dark)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/shared/glassdialog/confirm-(tap-to-open) (dark, high contrast)':
      KnownGap(1, _lowContrast),
  'components/shared/glassdialog/confirm-(tap-to-open) (light)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/shared/glassdialog/confirm-(tap-to-open) (light, high contrast)':
      KnownGap(1, _lowContrast),
  'components/shared/glassdialog/playground (dark)': KnownGap(1, _lowContrast),
  'components/shared/glassdialog/playground (dark, high contrast)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/shared/glassdialog/playground (light)': KnownGap(1, _lowContrast),
  'components/shared/glassdialog/playground (light, high contrast)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/shared/navlabel/in-a-rail-slot (light)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/shared/navlabel/in-a-rail-slot (light, high contrast)': KnownGap(
    1,
    _lowContrast,
  ),
  'components/shared/nearbyairportssection/states (dark)': KnownGap(
    3,
    _thisBranch,
  ),
  'components/shared/nearbyairportssection/states (dark, high contrast)':
      KnownGap(3, _thisBranch),
  'components/shared/thermalbutton/tones-and-states (dark)': KnownGap(
    2,
    _lowContrast,
  ),
  'components/shared/thermalbutton/tones-and-states (dark, high contrast)':
      KnownGap(2, _lowContrast),
  'components/shared/thermalbutton/tones-and-states (light)': KnownGap(
    2,
    _lowContrast,
  ),
  'components/shared/thermalbutton/tones-and-states (light, high contrast)':
      KnownGap(2, _lowContrast),
  'screens/auth/loginscreen/default (dark)': KnownGap(6, _lowContrast),
  'screens/auth/loginscreen/default (dark, high contrast)': KnownGap(
    6,
    _lowContrast,
  ),
  'screens/auth/loginscreen/default (light)': KnownGap(4, _lowContrast),
  'screens/auth/loginscreen/default (light, high contrast)': KnownGap(
    6,
    _lowContrast,
  ),
  'screens/trips/tripdetailsscreen/default (dark)': KnownGap(4, _thisBranch),
  'screens/trips/tripdetailsscreen/default (dark, high contrast)': KnownGap(
    4,
    _thisBranch,
  ),
  'screens/trips/tripdetailsscreen/default (light)': KnownGap(2, _lowContrast),
  'screens/trips/tripdetailsscreen/default (light, high contrast)': KnownGap(
    2,
    _lowContrast,
  ),
};
