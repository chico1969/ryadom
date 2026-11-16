import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/ryadom/readable_theme.dart';
import 'package:flutter_hbb/ryadom/home_content.dart';

void main() {
  testWidgets(
      'home keeps readable surfaces and a labelled network action in dark mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(920, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final target = TextEditingController();
    addTearDown(target.dispose);
    var networkOpened = 0;
    var settingsOpened = 0;
    await tester.pumpWidget(MaterialApp(
        theme: ryadomReadableTheme(ThemeData.dark()),
        home: Scaffold(
            body: RyadomHomeContent(
                localId: '123456789',
                target: target,
                computers: const [
                  RyadomComputer(
                      id: 'saved', name: 'Ноутбук', code: '987654321')
                ],
                onConnect: () {},
                onOpenComputer: (_) {},
                onCopy: () {},
                onSetPassword: () {},
                onSettings: () => settingsOpened++,
                onNetwork: () => networkOpened++))));
    final background = tester
        .widget<ColoredBox>(find
            .descendant(
                of: find.byType(RyadomHomeContent),
                matching: find.byType(ColoredBox))
            .first)
        .color;
    final panel = (tester
            .widget<DecoratedBox>(find
                .ancestor(
                    of: find.text('Дать доступ'),
                    matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration)
        .color!;
    expect(background.computeLuminance(), lessThan(0.1));
    expect(panel.computeLuminance(), lessThan(0.1));
    double contrast(Color text, Color surface) {
      final a = text.computeLuminance(), b = surface.computeLuminance();
      return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
    }

    for (final text in [
      'Дать доступ',
      'Ваш ID компьютера',
      '123 456 789',
      '987 654 321',
      'Ноутбук'
    ]) {
      final widget = tester.widget(find.text(text));
      final style =
          widget is Text ? widget.style : (widget as EditableText).style;
      expect(contrast(style!.color!, panel), greaterThanOrEqualTo(4.5),
          reason: text);
    }
    for (final label in ['Настройки', 'P2P / TURN']) {
      final button = tester.widget<TextButton>(find
          .ancestor(
              of: find.text(label),
              matching:
                  find.byWidgetPredicate((widget) => widget is TextButton))
          .first);
      expect(contrast(button.style!.foregroundColor!.resolve({})!, background),
          greaterThanOrEqualTo(4.5),
          reason: label);
    }
    expect(find.text('Тестовая сборка'), findsNothing);
    expect(find.byTooltip('Настройки'), findsOneWidget);
    expect(find.byTooltip('Настройки подключения'), findsOneWidget);
    await tester.tap(find.text('P2P / TURN'));
    expect(networkOpened, 1);
    await tester.tap(find.text('Настройки'));
    expect(settingsOpened, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('history shows multiple compact rows of numeric IDs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(920, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final target = TextEditingController();
    addTearDown(target.dispose);
    String? chosen;
    await tester.pumpWidget(MaterialApp(
        theme: ryadomReadableTheme(ThemeData()),
        home: Scaffold(
            body: RyadomHomeContent(
                localId: '123456789',
                target: target,
                computers: List.generate(
                    20,
                    (i) => RyadomComputer(
                        id: 'identity-$i',
                        name: 'Компьютер $i',
                        code: '${100000000 + i}')),
                onConnect: () {},
                onCopy: () {},
                onSetPassword: () {},
                onHelpP2P: () {},
                onOpenComputer: (id) => chosen = id))));
    final first = tester.getRect(find.text('100 000 000'));
    final second = tester.getRect(find.text('100 000 001'));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.left));
    expect(tester.getRect(find.text('100 000 005')).bottom,
        lessThanOrEqualTo(520));
    await tester.tap(find.text('100 000 002'));
    expect(chosen, 'identity-2');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'registration denial disables sharing and paused receiving can be enabled',
      (tester) async {
    final target = TextEditingController();
    addTearDown(target.dispose);
    var receivingStarted = false;
    for (final paused in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          theme: ryadomReadableTheme(ThemeData()),
          home: Scaffold(
              body: RyadomHomeContent(
                  localId: '',
                  target: target,
                  computers: const [],
                  registrationFailed: true,
                  registrationMessage: paused
                      ? 'Приём подключений выключен.'
                      : 'Служба поиска запретила доступ (HTTP 403).',
                  onStartReceiving:
                      paused ? () => receivingStarted = true : null,
                  onConnect: () {},
                  onOpenComputer: (_) {},
                  onCopy: () {},
                  onSetPassword: () {}))));
      expect(find.text('ID недоступен'), findsOneWidget);
      expect(find.text('Получаем ID…'), findsNothing);
      if (paused) {
        expect(find.text('Скопировать ID'), findsNothing);
        await tester.tap(find.text('Включить приём'));
        expect(receivingStarted, isTrue);
      } else {
        expect(
            tester
                .widget<OutlinedButton>(find
                    .byWidgetPredicate((widget) => widget is OutlinedButton))
                .onPressed,
            isNull);
      }
    }
  });
  testWidgets('main actions fit compact windows and larger text',
      (tester) async {
    final target = TextEditingController();
    addTearDown(target.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final profile in [
      (const Size(920, 520), 1.0),
      (const Size(760, 440), 1.0),
      (const Size(760, 440), 1.25),
      (const Size(760, 440), 1.5),
      (const Size(920, 560), 1.5),
    ]) {
      await tester.binding.setSurfaceSize(profile.$1);
      await tester.pumpWidget(MaterialApp(
          theme: ryadomReadableTheme(ThemeData()),
          home: MediaQuery(
              data: MediaQueryData(
                  size: profile.$1, textScaler: TextScaler.linear(profile.$2)),
              child: Scaffold(
                  body: RyadomHomeContent(
                localId: '123456789',
                target: target,
                error: 'Введите полный ID компьютера Рядом',
                computers: List.generate(
                    20,
                    (index) => RyadomComputer(
                        id: 'computer-$index', name: 'Компьютер $index')),
                onConnect: () {},
                onCopy: () {},
                onSetPassword: () {},
                onSettings: () {},
                onNetwork: () {},
                onHelpP2P: () {},
                onOpenComputer: (_) {},
              )))));
      await tester.pump();
      expect(find.text('123 456 789'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'Window ${profile.$1}, text ${profile.$2}');
      for (final action in [
        find.text('Скопировать ID'),
        find.byTooltip('Постоянный пароль'),
        find.text('Помочь прямому подключению'),
        find.text('Настройки'),
        find.text('P2P / TURN'),
        find.byType(TextField)
      ]) {
        final bounds = tester.getRect(action);
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(profile.$1.height));
      }
      final connect =
          find.byWidgetPredicate((widget) => widget is FilledButton);
      expect(
          tester.getRect(connect).bottom, lessThanOrEqualTo(profile.$1.height));
    }
  });
}
