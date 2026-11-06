import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/glass_surfaces.dart';
import 'package:map_my_friends/components/shared/thermal_button.dart';
import 'package:map_my_friends/utils/app_theme.dart';

/// Hosts a button that runs [onPressed] with a context under the app's
/// Navigator and ScaffoldMessenger.
Widget _launcher(void Function(BuildContext context) onPressed) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => onPressed(context),
          child: const Text('go'),
        ),
      ),
    ),
  ),
);

void main() {
  group('GlassSheet', () {
    testWidgets('show presents the builder content with a drag handle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _launcher(
          (context) => GlassSheet.show<void>(
            context,
            builder: (_) => const Text('sheet body'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('sheet body'), findsOneWidget);
      final handle = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints ==
                const BoxConstraints.tightFor(width: 36, height: 4),
      );
      expect(handle, findsOneWidget);
    });

    testWidgets('a short sheet can drop the handle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassSheet(showHandle: false, child: Text('card')),
          ),
        ),
      );

      expect(find.text('card'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints ==
                  const BoxConstraints.tightFor(width: 36, height: 4),
        ),
        findsNothing,
      );
    });

    testWidgets('show resolves to the value the sheet pops with', (
      tester,
    ) async {
      String? result;
      await tester.pumpWidget(
        _launcher((context) async {
          result = await GlassSheet.show<String>(
            context,
            builder: (sheet) => TextButton(
              onPressed: () => Navigator.of(sheet).pop('picked'),
              child: const Text('pick'),
            ),
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      expect(result, 'picked');
      expect(find.text('pick'), findsNothing);
    });

    testWidgets('actions lists each choice, closes, then runs it', (
      tester,
    ) async {
      final chosen = <String>[];
      var sheetOpenWhenRun = true;
      await tester.pumpWidget(
        _launcher(
          (context) => GlassSheet.actions(
            context,
            title: 'Add a photo',
            actions: [
              SheetAction(
                icon: Icons.camera_alt,
                label: 'Take a photo',
                onTap: () => chosen.add('camera'),
              ),
              SheetAction(
                icon: Icons.photo_library,
                label: 'Choose from gallery',
                onTap: () {
                  chosen.add('gallery');
                  sheetOpenWhenRun = false;
                },
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Add a photo'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
      expect(find.text('Take a photo'), findsOneWidget);

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(chosen, ['gallery']);
      expect(sheetOpenWhenRun, isFalse);
      expect(find.text('Take a photo'), findsNothing);
    });

    testWidgets('actions without a title shows only the choices', (
      tester,
    ) async {
      await tester.pumpWidget(
        _launcher(
          (context) => GlassSheet.actions(
            context,
            actions: [
              SheetAction(icon: Icons.delete, label: 'Remove', onTap: () {}),
            ],
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Remove'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GlassSheet),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
    });
  });

  group('GlassDialog.confirm', () {
    Future<bool?> ask(
      WidgetTester tester, {
      ThermalButtonTone tone = ThermalButtonTone.primary,
      String? message = 'This cannot be undone.',
    }) async {
      bool? answer;
      await tester.pumpWidget(
        _launcher((context) async {
          answer = await GlassDialog.confirm(
            context,
            title: 'Delete Ada?',
            message: message,
            confirmLabel: 'Delete',
            cancelLabel: 'Keep',
            tone: tone,
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('shows the question and both answers', (tester) async {
      await ask(tester, tone: ThermalButtonTone.danger);

      expect(find.text('Delete Ada?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      final confirm = tester.widget<ThermalButton>(
        find.widgetWithText(ThermalButton, 'Delete'),
      );
      final cancel = tester.widget<ThermalButton>(
        find.widgetWithText(ThermalButton, 'Keep'),
      );
      expect(confirm.tone, ThermalButtonTone.danger);
      // The way out never carries the same weight as the action.
      expect(cancel.tone, ThermalButtonTone.secondary);
    });

    testWidgets('resolves true when confirmed', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        _launcher((context) async {
          answer = await GlassDialog.confirm(
            context,
            title: 'Sure?',
            confirmLabel: 'Yes',
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      // No message was given, so only the title and the buttons are shown.
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(answer, isTrue);
      expect(find.text('Sure?'), findsNothing);
    });

    testWidgets('resolves false when declined', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        _launcher((context) async {
          answer = await GlassDialog.confirm(
            context,
            title: 'Sure?',
            confirmLabel: 'Yes',
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(answer, isFalse);
    });

    testWidgets('resolves false when dismissed by the barrier', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        _launcher((context) async {
          answer = await GlassDialog.confirm(
            context,
            title: 'Sure?',
            confirmLabel: 'Yes',
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('Sure?'), findsNothing);
      expect(answer, isFalse);
    });
  });

  group('GlassDialog.panel', () {
    testWidgets('shows content with a single way out', (tester) async {
      var closed = false;
      await tester.pumpWidget(
        _launcher((context) async {
          await GlassDialog.panel(
            context,
            title: 'Pin colour',
            content: const Text('swatches'),
            dismissLabel: 'Close',
          );
          closed = true;
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Pin colour'), findsOneWidget);
      expect(find.text('swatches'), findsOneWidget);
      expect(find.byType(ThermalButton), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(find.text('swatches'), findsNothing);
    });
  });

  testWidgets('a dialog with nothing to confirm shows only its dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassDialog(title: 'Heads up', message: 'FYI'),
        ),
      ),
    );

    expect(find.text('Heads up'), findsOneWidget);
    expect(find.text('FYI'), findsOneWidget);
    expect(find.byType(ThermalButton), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  group('GlassToast', () {
    Future<void> toast(
      WidgetTester tester,
      void Function(BuildContext context) show,
    ) async {
      await tester.pumpWidget(_launcher(show));
      await tester.tap(find.text('go'));
      await tester.pump();
    }

    /// The 3px accent rule down the toast's leading edge.
    Color accent(WidgetTester tester) => tester
        .widget<Container>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxWidth == 3,
            ),
          ),
        )
        .color!;

    testWidgets('a neutral toast carries the message and no icon', (
      tester,
    ) async {
      await toast(tester, (c) => GlassToast.show(c, 'Saved draft'));
      final scheme = Theme.of(tester.element(find.text('go'))).colorScheme;

      expect(find.text('Saved draft'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)),
        findsNothing,
      );
      expect(accent(tester), scheme.primary);
    });

    testWidgets('success confirms with a check in the secondary colour', (
      tester,
    ) async {
      await toast(tester, (c) => GlassToast.success(c, 'Trip saved'));
      final scheme = Theme.of(tester.element(find.text('go'))).colorScheme;

      expect(find.text('Trip saved'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(accent(tester), scheme.secondary);
    });

    testWidgets('failure reads in the thermal core with an error icon', (
      tester,
    ) async {
      await toast(tester, (c) => GlassToast.failure(c, 'Could not save'));

      expect(find.text('Could not save'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(accent(tester), MapPalette.thermalCore);
    });

    testWidgets('a custom icon replaces the tone icon', (tester) async {
      await toast(
        tester,
        (c) => GlassToast.show(
          c,
          'Moved',
          tone: ToastTone.success,
          icon: Icons.swap_horiz,
        ),
      );

      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('the action dismisses the toast and runs the follow-up', (
      tester,
    ) async {
      var undone = 0;
      await toast(
        tester,
        (c) => GlassToast.show(
          c,
          'Removed Ada',
          actionLabel: 'Undo',
          onAction: () => undone++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(undone, 1);
      expect(find.text('Removed Ada'), findsNothing);
    });

    testWidgets('an action label without a handler is not shown', (
      tester,
    ) async {
      await toast(
        tester,
        (c) => GlassToast.show(c, 'Removed Ada', actionLabel: 'Undo'),
      );

      expect(find.text('Removed Ada'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('a new toast replaces the one showing', (tester) async {
      var count = 0;
      await toast(tester, (c) => GlassToast.show(c, 'Toast ${++count}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Toast 1'), findsNothing);
      expect(find.text('Toast 2'), findsOneWidget);
    });

    testWidgets('disappears on its own after four seconds', (tester) async {
      await toast(tester, (c) => GlassToast.show(c, 'Brief'));
      await tester.pumpAndSettle();
      expect(find.text('Brief'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Brief'), findsNothing);
    });

    testWidgets('does nothing without a ScaffoldMessenger', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              GlassToast.show(context, 'Nowhere to go');
              return const SizedBox();
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Nowhere to go'), findsNothing);
    });
  });
}
