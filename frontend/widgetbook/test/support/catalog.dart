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
