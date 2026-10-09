import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/ambient_field.dart';
import 'package:map_my_friends/components/shared/glass_empty_state.dart';
import 'package:map_my_friends/utils/app_theme.dart';

/// The room a catalog entry is shown in.
///
/// Glass in this app is only glass over something: a [GlassContainer] on a
/// flat canvas samples a flat canvas and renders as a tinted box, which is a
/// material the app never displays. So every entry stands up what the shell
/// provides in production — the [AmbientField] and one [BackdropGroup] over it
/// (GlassContainer asserts on the latter in debug).
///
/// The stage also owns a [Navigator]. Widgetbook's own navigator sits above
/// the theme, locale, and bloc providers the entry is wrapped in, so a route
/// pushed onto it would render unthemed and without the blocs it reads. With
/// a navigator here, People → Person details → Edit and every bottom sheet
/// stay inside the same scope, and inside the selected device frame.
class Stage extends StatefulWidget {
  /// A component, centred and padded on the field.
  const Stage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MapSpacing.md),
    this.alignment = Alignment.center,
    this.maxWidth = 480,
  }) : field = true,
       pushedFrom = null;

  /// A full screen that, like the tab screens, expects the shell to provide
  /// the field and backdrop group.
  const Stage.screen({super.key, required this.child})
    : padding = EdgeInsets.zero,
      alignment = null,
      maxWidth = null,
      field = true,
      pushedFrom = null;

  /// Something that brings its own room — a screen that builds an
  /// `AmbientScaffold`, a live map — so the stage adds nothing behind it.
  const Stage.route({super.key, required this.child})
    : padding = EdgeInsets.zero,
      alignment = null,
      maxWidth = null,
      field = false,
      pushedFrom = null;

  /// A screen the app only ever pushes, shown pushed: it gets its back
  /// affordance, and when it pops itself (Register does on success) the entry
  /// lands on a page saying so instead of on nothing.
  const Stage.pushed({
    super.key,
    required this.child,
    required String this.pushedFrom,
  }) : padding = EdgeInsets.zero,
       alignment = null,
       maxWidth = null,
       field = false;

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Null fills the viewport.
  final AlignmentGeometry? alignment;

  /// Caps a component's width so a phone-sized widget is not stretched across
  /// a desktop viewport. Null leaves the width to the viewport.
  final double? maxWidth;

  /// Whether to paint the Ambient Field behind [child].
  final bool field;

  /// For [Stage.pushed]: the name of the screen it is pushed from.
  final String? pushedFrom;

  @override
  State<Stage> createState() => _StageState();
}

class _StageState extends State<Stage> {
  bool _popped = false;

  Widget _room(Widget content) {
    return BackdropGroup(
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: AmbientField()),
          Positioned.fill(
            child: Material(type: MaterialType.transparency, child: content),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    Widget content = widget.child;
    final alignment = widget.alignment;
    if (alignment != null) {
      content = Align(
        alignment: alignment,
        child: SingleChildScrollView(
          padding: widget.padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.maxWidth ?? double.infinity,
            ),
            child: content,
          ),
        ),
      );
    }
    return widget.field ? _room(content) : content;
  }

  @override
  Widget build(BuildContext context) {
    final from = widget.pushedFrom;

    return Navigator(
      pages: <Page<void>>[
        if (from != null)
          MaterialPage<void>(
            key: const ValueKey<String>('underlay'),
            child: _room(
              Center(
                child: GlassEmptyState(
                  icon: Icons.undo,
                  title: 'Back on $from',
                  message:
                      'The screen popped itself, as it does in the app. '
                      'This is where the navigation stack returns.',
                  actionLabel: 'Open it again',
                  actionIcon: Icons.redo,
                  onAction: () => setState(() => _popped = false),
                ),
              ),
            ),
          ),
        if (from == null || !_popped)
          // A stable key, so a knob change updates this page's child in place
          // rather than replacing the route (and dropping anything pushed on
          // top of it).
          MaterialPage<void>(
            key: const ValueKey<String>('stage'),
            child: _content(),
          ),
      ],
      onDidRemovePage: (page) {
        if (page.key == const ValueKey<String>('stage')) {
          setState(() => _popped = true);
        }
      },
    );
  }
}
