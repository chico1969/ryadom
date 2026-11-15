import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/ryadom/readable_theme.dart';
import 'package:flutter_hbb/ryadom/session_hints.dart';
import 'package:flutter_hbb/ryadom/remote_cursor.dart';
import 'package:flutter_hbb/ryadom/home_content.dart';
import 'package:flutter_hbb/ryadom/codec_score.dart';

void main() {
  testWidgets(
      'remote cursor hides after five seconds and only movement shows it again',
      (tester) async {
    Future<void> cursor(Offset position, {double scale = 1}) =>
        tester.pumpWidget(MaterialApp(
            theme: ryadomReadableTheme(ThemeData()),
            home: RyadomRemoteCursor(
                position: position, image: null, x: 10, y: 20, scale: scale)));
    Finder painted() => find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is RyadomRemoteCursorPainter);
    await cursor(const Offset(10, 20));
    expect(painted(), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await cursor(const Offset(10, 20), scale: 2);
    await tester.pump(const Duration(seconds: 1));
    expect(painted(), findsNothing);
    await cursor(const Offset(10, 20));
    expect(painted(), findsNothing);
    await cursor(const Offset(11, 20));
    expect(painted(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
  test('codec selection uses measurements and rejects idle samples', () {
    const vp8 = CodecMeasurement('vp8', 30, 45, 1024 * 1024);
    const slowVp9 = CodecMeasurement('vp9', 18, 50, 300000);
    expect(chooseMeasuredCodec([slowVp9, vp8])?.codec, 'vp8');
    const efficientVp9 = CodecMeasurement('vp9', 30, 45, 300000);
    expect(chooseMeasuredCodec([vp8, efficientVp9])?.codec, 'vp9');
    expect(
        chooseMeasuredCodec([const CodecMeasurement('vp8', 0, 30, 0)]), isNull);
  });
  testWidgets('toolbar tooltip appears on hover without a waiting delay',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ryadomReadableTheme(ThemeData()),
        home: RyadomSessionHints(
            child: Center(
          child: IconButton(
              tooltip: 'Клавиатура',
              onPressed: () {},
              icon: const Icon(Icons.keyboard)),
        ))));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Клавиатура'), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'remote cursor is orange at its scaled position with transparent surroundings',
      (tester) async {
    await tester.runAsync(() async {
      final source = ui.PictureRecorder();
      Canvas(source).drawRect(
          const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = Colors.black);
      final shape = await source.endRecording().toImage(6, 6);
      for (final scale in [1.0, 2.0]) {
        final recorder = ui.PictureRecorder();
        RyadomRemoteCursorPainter(image: shape, x: 4, y: 5, scale: scale)
            .paint(Canvas(recorder), const Size(32, 32));
        final rendered = await recorder.endRecording().toImage(32, 32);
        final rgba =
            await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
        final index =
            (((5 + 1) * scale).toInt() * 32 + ((4 + 1) * scale).toInt()) * 4;
        expect(rgba!.buffer.asUint8List(index, 4), [255, 138, 28, 255]);
        expect(rgba.getUint8(3), 0);
        rendered.dispose();
      }
      shape.dispose();
    });
  });

  testWidgets('history reconnects by persistent device identity',
      (tester) async {
    final target = TextEditingController();
    addTearDown(target.dispose);
    const id = 'ryadom-0123456789abcdef0123456789abcdef';
    String? selected;
    await tester.pumpWidget(MaterialApp(
        theme: ryadomReadableTheme(ThemeData()),
        home: Scaffold(
            body: RyadomHomeContent(
          localId: '123456789',
          target: target,
          computers: const [
            RyadomComputer(
                id: id, name: 'Ноутбук родственника', code: '987654321')
          ],
          onConnect: () {},
          onCopy: () {},
          onSetPassword: () {},
          onOpenComputer: (value) => selected = value,
        ))));
    expect(find.text('987 654 321'), findsOneWidget);
    await tester.tap(find.text('987 654 321'));
    expect(selected, id);
  });
}
