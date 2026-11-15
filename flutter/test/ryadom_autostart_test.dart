import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/ryadom/autostart.dart';

void main() {
  testWidgets('autostart is checked by default and can be unchecked', (tester) async {
    bool? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: RyadomAutostartOption(onChanged: (value) => selected = value))));
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
    await tester.tap(find.text('Запускать вместе с Windows'));
    expect(selected, isFalse);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: RyadomAutostartOption(value: false, onChanged: (value) => selected = value))));
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
    await tester.tap(find.text('Запускать вместе с Windows'));
    expect(selected, isTrue);
  });
}
