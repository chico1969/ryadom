import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/ryadom/autostart.dart';
import 'package:flutter_hbb/ryadom/install_privacy.dart';

void main() {
  testWidgets('network consent serializes separately from Windows autostart',
      (tester) async {
    var network = true, autostart = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Column(children: [
                      RyadomAutostartOption(
                          value: autostart,
                          onChanged: (value) =>
                              setState(() => autostart = value)),
                      RyadomInstallPrivacy(
                          backgroundNetwork: network,
                          onChanged: (value) => setState(() => network = value))
                    ])))));
    String options() => '${autostart ? 'autostart' : 'no-autostart'}'
        '${ryadomInstallNetworkOption(network)}';
    expect(options(), 'autostart --ryadom-background-network');
    await tester
        .tap(find.text('Разрешить фоновую связь для входящих подключений'));
    await tester.pump();
    expect(options(), 'autostart --ryadom-no-background-network');
    await tester.tap(find.text('Запускать вместе с Windows'));
    await tester.pump();
    expect(options(), 'no-autostart --ryadom-no-background-network');
    await tester
        .tap(find.text('Разрешить фоновую связь для входящих подключений'));
    await tester.pump();
    expect(options(), 'no-autostart --ryadom-background-network');
  });

  testWidgets('own privacy disclosure opens locally without a network request',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RyadomInstallPrivacy(
                backgroundNetwork: false, onChanged: (_) {}))));
    expect(find.text('Политика на GitHub'), findsOneWidget);
    await tester.tap(find.text('Как используются данные'));
    await tester.pumpAndSettle();
    expect(find.text('Конфиденциальность «Рядом»'), findsOneWidget);
    expect(find.textContaining('открытый ключ устройства'), findsOneWidget);
    expect(find.textContaining('Настроенный TURN'), findsOneWidget);
    expect(find.textContaining('хранятся локально'), findsOneWidget);
    expect(find.textContaining('rustdesk.com'), findsNothing);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('Конфиденциальность «Рядом»'), findsNothing);
  });

  testWidgets('privacy controls stay reachable in a compact dark installer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
            child: Scaffold(
                body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: const SingleChildScrollView(
                        child: RyadomInstallPrivacy(
                            backgroundNetwork: true, onChanged: null)))))));
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    await tester.ensureVisible(find.text('Политика на GitHub'));
    expect(find.text('Политика на GitHub').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
