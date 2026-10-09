import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';
import 'ambient_field.dart';

/// A screen that brings its own room.
///
/// The shell paints one [AmbientField] beneath the tab screens, but a route
/// pushed onto the [Navigator] covers the shell completely — a transparent
/// scaffold there would show the outgoing screen, not the field. Every
/// full-screen route therefore owns its own field and its own [BackdropGroup].
///
/// One group per route is deliberate, not incidental: route transitions
/// overlap the outgoing and incoming screens, and two `BackdropFilter.grouped`
/// surfaces sharing a key across that overlap render as though only one of them
/// applied. See [GlassContainer]'s notes on the shared backdrop sample.
class AmbientScaffold extends StatelessWidget {
  final Widget body;

  /// The surface's [GlassHeader], laid above the body. Prefer this to
  /// [appBar]: a Material app bar inside this shell is a second navigation
  /// chrome with its own material, type, and interaction feedback.
  final Widget? header;

  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final bool? resizeToAvoidBottomInset;

  /// Content runs under the app bar by default. The chrome on this surface is
  /// glass, and glass that content never passes beneath has nothing to refract.
  final bool extendBodyBehindAppBar;

  /// Pins the surface to one appearance regardless of the user's setting.
  ///
  /// The pre-auth flow uses this. It runs before there is a signed-in person
  /// whose preference we could honour, and it reads as the product's title
  /// sequence: the void, once, before the room lights come up.
  final Brightness? appearance;

  const AmbientScaffold({
    super.key,
    required this.body,
    this.header,
    this.appBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset,
    this.extendBodyBehindAppBar = true,
    this.appearance,
  });

  @override
  Widget build(BuildContext context) {
    final Widget surface = BackdropGroup(
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: AmbientField()),
          Positioned.fill(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              extendBodyBehindAppBar: extendBodyBehindAppBar,
              resizeToAvoidBottomInset: resizeToAvoidBottomInset,
              appBar: appBar,
              floatingActionButton: floatingActionButton,
              body: header == null
                  ? body
                  : Column(
                      children: <Widget>[
                        header!,
                        Expanded(child: body),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );

    if (appearance == null) return surface;
    return Theme(
      data: appearance == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      child: surface,
    );
  }
}
