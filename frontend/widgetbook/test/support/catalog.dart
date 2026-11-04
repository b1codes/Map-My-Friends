import 'package:flutter/material.dart';
import 'package:map_my_friends_widgetbook/support/media_addon.dart';
import 'package:widgetbook/widgetbook.dart';

/// A node's place in the tree, as the path Widgetbook routes to.
String routeOf(String prefix, WidgetbookNode node) =>
    '$prefix${node.name}'.replaceAll(' ', '-').toLowerCase();

/// Every use case in [nodes], as the path Widgetbook routes to, e.g.
/// `components/map/mapcontrols/over-the-map`.
List<String> useCasePaths(List<WidgetbookNode> nodes, [String prefix = '']) {
  return [
    for (final node in nodes)
      if (node is WidgetbookUseCase)
        routeOf(prefix, node)
      else
        ...useCasePaths(node.children ?? const [], '$prefix${node.name}/'),
  ];
}

/// The route that opens [path] in preview mode, with the catalog's addons
/// set: [theme] is `Light` or `Dark`. Group names come from the addons
/// themselves, as the catalog reads them.
///
/// Motion is reduced by default: the Ambient Field drifts and the Chromatic
/// Pulse breathes for as long as they are on screen, so with motion on, what
/// a test sees is whichever frame it reached.
String routeTo(
  String path, {
  required String theme,
  bool reduceMotion = true,
  bool highContrast = false,
  double textScale = 1.0,
}) {
  final themeGroup = MaterialThemeAddon(
    themes: [WidgetbookTheme(name: theme, data: ThemeData())],
  ).groupName;
  final query = {
    'path': path,
    themeGroup: FieldCodec.encodeQueryGroup({'name': theme}),
    MediaPreferencesAddon().groupName: FieldCodec.encodeQueryGroup({
      'reduceMotion': '$reduceMotion',
      'highContrast': '$highContrast',
    }),
    if (textScale != 1.0)
      TextScaleAddon().groupName: FieldCodec.encodeQueryGroup({
        'factor': '$textScale',
      }),
  };
  final params = query.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return '/?$params&preview';
}
