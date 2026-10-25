import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/custom_text_form_field.dart';

void main() {
  Future<void> pumpField(WidgetTester tester, Widget field) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Form(child: field)),
        ),
      );

  TextField innerField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('shows its label and writes into the controller', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    await pumpField(
      tester,
      CustomTextFormField(
        controller: controller,
        labelText: 'City',
        onChanged: changes.add,
      ),
    );

    expect(find.text('City'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Lisbon');

    expect(controller.text, 'Lisbon');
    expect(changes, ['Lisbon']);
  });

  testWidgets('shows the validator message when the form validates', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: CustomTextFormField(
              labelText: 'Email',
              validator: (v) =>
                  (v ?? '').contains('@') ? null : 'Enter an email',
            ),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter an email'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'ada@example.com');
    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('Enter an email'), findsNothing);
  });

  testWidgets('obscures text and passes through the keyboard type', (
    tester,
  ) async {
    await pumpField(
      tester,
      const CustomTextFormField(
        labelText: 'Password',
        obscureText: true,
        keyboardType: TextInputType.visiblePassword,
      ),
    );

    final field = innerField(tester);
    expect(field.obscureText, isTrue);
    expect(field.keyboardType, TextInputType.visiblePassword);
  });

  testWidgets('a read-only field reports taps instead of taking input', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Pick a date');
    addTearDown(controller.dispose);
    var taps = 0;
    await pumpField(
      tester,
      CustomTextFormField(
        controller: controller,
        labelText: 'Birthday',
        readOnly: true,
        onTap: () => taps++,
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    expect(taps, 1);
    expect(innerField(tester).readOnly, isTrue);
  });

  testWidgets('shows prefix and suffix icons', (tester) async {
    await pumpField(
      tester,
      const CustomTextFormField(
        labelText: 'Search',
        prefixIcon: Icon(Icons.search),
        suffixIcon: Icon(Icons.clear),
      ),
    );

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);
  });

  testWidgets('is single line by default and multi-line on request', (
    tester,
  ) async {
    await pumpField(tester, const CustomTextFormField(labelText: 'Name'));
    expect(innerField(tester).maxLines, 1);

    await pumpField(
      tester,
      const CustomTextFormField(labelText: 'Notes', maxLines: 4),
    );
    expect(innerField(tester).maxLines, 4);
    expect(innerField(tester).decoration!.alignLabelWithHint, isTrue);
  });

  testWidgets('focus and error borders follow the theme', (tester) async {
    await pumpField(tester, const CustomTextFormField(labelText: 'Name'));
    final scheme = Theme.of(tester.element(find.byType(TextField))).colorScheme;
    final decoration = innerField(tester).decoration!;

    expect(
      (decoration.focusedBorder! as OutlineInputBorder).borderSide.color,
      scheme.primary,
    );
    expect(
      (decoration.errorBorder! as OutlineInputBorder).borderSide.color,
      scheme.error,
    );
    expect(decoration.filled, isTrue);
  });
}
