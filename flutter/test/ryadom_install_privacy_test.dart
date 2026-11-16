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

  testWidgets('installation actions stay visible without scrolling the form',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final profile in [
      (const Size(776, 585), 1.0),
      (const Size(600, 560), 1.25)
    ]) {
      await tester.binding.setSurfaceSize(profile.$1);
      var installed = 0;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(profile.$2)),
              child: Scaffold(
                  appBar: const PreferredSize(
                      preferredSize: Size.fromHeight(30), child: SizedBox()),
                  body: SingleChildScrollView(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          child: Column(children: [
                            const SizedBox(height: 160),
                            RyadomAutostartOption(
                                value: true, onChanged: (_) {}),
                            RyadomInstallPrivacy(
                                backgroundNetwork: true, onChanged: (_) {}),
                            const SizedBox(height: 600)
                          ]))),
                  bottomNavigationBar: RyadomInstallFooter(
                      onInstall: () => installed++,
                      onCancel: () {},
                      showRunWithoutInstall: true,
                      onRunWithoutInstall: () {})))));
      final install = find.text('Принять и установить');
      final initialFooter = tester.getRect(find.byType(RyadomInstallFooter));
      expect(initialFooter.bottom, lessThanOrEqualTo(profile.$1.height));
      expect(install.hitTestable(), findsOneWidget);
      if (profile.$2 == 1.0) {
        expect(find.text('Запускать вместе с Windows').hitTestable(),
            findsOneWidget);
        expect(
            find
                .text('Разрешить фоновую связь для входящих подключений')
                .hitTestable(),
            findsOneWidget);
      }
      await tester.tap(install);
      expect(installed, 1);
      await tester.ensureVisible(find.text('Политика на GitHub'));
      expect(tester.getRect(find.byType(RyadomInstallFooter)), initialFooter);
      expect(install.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
