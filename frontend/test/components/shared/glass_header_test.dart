import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/glass_header.dart';

void main() {
  Widget host(Widget header, {double topPadding = 0}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(top: topPadding)),
      child: BackdropGroup(
        child: Scaffold(body: Column(children: [header])),
      ),
    ),
  );

  testWidgets('shows the title and an optional subtitle', (tester) async {
    await tester.pumpWidget(host(const GlassHeader(title: 'Friends')));
    expect(find.text('Friends'), findsOneWidget);

    await tester.pumpWidget(
      host(const GlassHeader(title: 'Ada Lovelace', subtitle: 'FAMILY')),
    );
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('FAMILY'), findsOneWidget);
  });

  testWidgets('clears the top safe area', (tester) async {
    await tester.pumpWidget(
      host(const GlassHeader(title: 'Friends'), topPadding: 40),
    );

    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(GlassHeader),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect((padding.padding as EdgeInsets).top, greaterThanOrEqualTo(40));
  });

  testWidgets('a root surface has no back button', (tester) async {
    await tester.pumpWidget(host(const GlassHeader(title: 'Friends')));

    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('showBack forces the back button on a root surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const GlassHeader(title: 'Friends', showBack: true)),
    );

    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('a pushed surface goes back when Back is tapped', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BackdropGroup(
                  child: const Scaffold(
                    body: Column(children: [GlassHeader(title: 'Details')]),
                  ),
                ),
              ),
            ),
            child: const Text('push'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsNothing);
    expect(find.text('push'), findsOneWidget);
  });

  testWidgets('showBack: false hides back even when it could pop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BackdropGroup(
                  child: const Scaffold(
                    body: Column(
                      children: [GlassHeader(title: 'Modal', showBack: false)],
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('push'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('each action is a labelled 48dp button that fires', (
    tester,
  ) async {
    final pressed = <String>[];
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        GlassHeader(
          title: 'Ada',
          actions: [
            HeaderAction(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onPressed: () => pressed.add('edit'),
            ),
            HeaderAction(
              icon: Icons.delete_outline,
              label: 'Delete',
              onPressed: () => pressed.add('delete'),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(pressed, ['delete', 'edit']);

    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Edit'))),
      matchesSemantics(
        label: 'Edit',
        tooltip: 'Edit',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.edit_outlined),
              matching: find.byType(SizedBox),
            )
            .first,
      ),
      const Size(48, 48),
    );
    semantics.dispose();
  });
}
