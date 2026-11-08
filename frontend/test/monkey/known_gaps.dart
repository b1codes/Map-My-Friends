// Problems the monkey finds that are already filed. A match is logged and
// counted, not failed, so the run stays useful for finding new ones; every
// other problem fails. When a task is fixed, delete its entry here: if the
// fix is incomplete, the monkey says so.
import 'monkey.dart';

/// A filed problem, recognised by its error report.
class KnownGap {
  const KnownGap(this.task, this.what, this.matches);

  /// The ClickUp task that tracks it.
  final String task;

  /// One line, for the log.
  final String what;

  /// Whether [report] (the error's description, up to its stack trace) is
  /// this problem, given the window and text size the monkey had set.
  final bool Function(String report, Monkey monkey) matches;
}

/// A layout overflow raised by a widget built in one of [files], past
/// [edge] ('right', 'bottom') if given.
bool _overflowIn(String report, List<String> files, {String? edge}) =>
    report.contains('overflowed by') &&
    (edge == null || report.contains('pixels on the $edge')) &&
    files.any(report.contains);

final knownGaps = <KnownGap>[
  KnownGap(
    'https://app.clickup.com/t/86bcxk6bb',
    'PersonCard / ContactRosterTile overflow with real fonts',
    (report, _) =>
        _overflowIn(report, ['person_card.dart', 'contact_roster_tile.dart']),
  ),
  KnownGap(
    'https://app.clickup.com/t/86bcyn5a6',
    'layouts overflow with large text',
    (report, monkey) =>
        monkey.textScale > 1 &&
        _overflowIn(report, [
          'person_card.dart',
          'contact_roster_tile.dart',
          'login_screen.dart',
          'unified_cluster_modal.dart',
          'glass_surfaces.dart',
        ]),
  ),
  KnownGap(
    'https://app.clickup.com/t/86bcrpgwz',
    'Log contact sheet overflows on short windows',
    (report, _) => _overflowIn(report, ['log_contact_sheet.dart']),
  ),
  KnownGap(
    'https://app.clickup.com/t/86bcqz5c1',
    'a long toast overflows instead of wrapping (item 2)',
    (report, _) => _overflowIn(report, ['glass_surfaces.dart'], edge: 'right'),
  ),
  KnownGap(
    'https://app.clickup.com/t/86bcqz5c1',
    'the cluster sheet overflows (item 4)',
    (report, _) => _overflowIn(report, ['unified_cluster_modal.dart']),
  ),
];
