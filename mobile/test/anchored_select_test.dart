import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sui_mobile/ui/widgets.dart';

void main() {
  testWidgets('anchored selector hugs the field, shows five rows and scrolls to the last option', (tester) async {
    var selected = 'one';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, setState) => AnchoredSelect<String>(
                  key: const ValueKey('select-under-test'),
                  value: selected,
                  label: 'Choice',
                  options: const [
                    SelectOption('one', 'One'),
                    SelectOption('two', 'Two'),
                    SelectOption('three', 'Three'),
                    SelectOption('four', 'Four'),
                    SelectOption('five', 'Five'),
                    SelectOption('six', 'Six'),
                  ],
                  onChanged: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('select-under-test')));
    await tester.pumpAndSettle();

    final target = tester.getRect(find.byKey(const ValueKey('select-under-test')));
    final menu = tester.getRect(find.byKey(const ValueKey('anchored-select-menu')));
    expect(menu.left, closeTo(target.left, 0.1));
    expect(menu.width, closeTo(target.width, 0.1));
    expect(menu.top, closeTo(target.bottom - 2, 0.1));
    expect(menu.height, closeTo(kMinInteractiveDimension * 5, 0.1));

    await tester.drag(find.byKey(const ValueKey('anchored-select-menu')), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Six'));
    await tester.pumpAndSettle();
    expect(selected, 'six');
    expect(find.byKey(const ValueKey('anchored-select-menu')), findsNothing);
  });
}
