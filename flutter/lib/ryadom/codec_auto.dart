import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'codec_score.dart';
import 'native_network_stub.dart' if (dart.library.io) 'native_network.dart';

const ryadomCodecAutoKey = 'ryadom-codec-auto';
final _controllers = <String, RyadomCodecController>{};
RyadomCodecController ryadomCodecController(FFI ffi) => _controllers
    .putIfAbsent(ffi.sessionId.toString(), () => RyadomCodecController(ffi));
void disposeRyadomCodec(FFI ffi) =>
    _controllers.remove(ffi.sessionId.toString())?.dispose();

class RyadomCodecController extends ChangeNotifier {
  RyadomCodecController(this.ffi);
  final FFI ffi;
  String status = 'Автовыбор кодека', _before = 'auto', _trial = '';
  final results = <CodecMeasurement>[];
  final _samples = <CodecMeasurement>[];
  final _clock = Stopwatch();
  Future<void> _writes = Future.value();
  int _epoch = 0;
  int _lastSampleMs = 0;
  bool _disposed = false, _running = false, _requireFullColor = false;
  bool get running => _running;
  bool _valid(int epoch) => !_disposed && !ffi.closed && epoch == _epoch;
  bool _controls() {
    if (ffi.closed || ffi.ffiModel.viewOnly) return false;
    try {
      return ryadomSessionControls(ffi.sessionId.toString());
    } catch (error) {
      debugPrint('Ryadom codec control state: $error');
      return false;
    }
  }

  void _status(String value) {
    status = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeCodec(String codec, {required bool send, int? epoch}) =>
      _serialize(() async {
        if (_disposed || (epoch != null && !_valid(epoch))) return;
        await bind.sessionPeerOption(
            sessionId: ffi.sessionId,
            name: kOptionCodecPreference,
            value: codec);
        if (send && (epoch == null || _valid(epoch)) && _controls()) {
          await bind.sessionChangePreferCodec(sessionId: ffi.sessionId);
        }
      });
  Future<void> beginIfAutomatic() async {
    try {
      final mode = await bind.sessionGetPeerOption(
          sessionId: ffi.sessionId, name: ryadomCodecAutoKey);
      final codec = await bind.sessionGetOption(
              sessionId: ffi.sessionId, arg: kOptionCodecPreference) ??
          '';
      if (mode == 'N' ||
          (mode.isEmpty && codec.isNotEmpty && codec != 'auto')) {
        _status('Ручной кодек: ${codec.toUpperCase()}');
        return;
      }
      await select('auto');
    } catch (error) {
      _status('Проверка кодеков недоступна: $error');
    }
  }

  Future<void> select(String codec) async {
    try {
      await _select(codec);
    } catch (error) {
      _status('Проверка кодеков недоступна: $error');
    }
  }

  Future<void> _select(String codec) async {
    if (codec == 'auto' && _running) return;
    final epoch = ++_epoch;
    if (codec != 'auto') {
      _running = false;
      await _serialize(() async {
        if (!_valid(epoch)) return;
        await bind.sessionPeerOption(
            sessionId: ffi.sessionId, name: ryadomCodecAutoKey, value: 'N');
        await bind.sessionPeerOption(
            sessionId: ffi.sessionId,
            name: kOptionCodecPreference,
            value: codec);
        if (_valid(epoch) && _controls()) {
          await bind.sessionChangePreferCodec(sessionId: ffi.sessionId);
        }
      });
      if (_valid(epoch)) _status('Ручной кодек: ${codec.toUpperCase()}');
      return;
    }
    if (!_controls()) {
      _status('Автопроверка доступна управляющему');
      return;
    }
    await _writes;
    if (!_valid(epoch)) return;
    _before = await bind.sessionGetOption(
            sessionId: ffi.sessionId, arg: kOptionCodecPreference) ??
        'auto';
    if (_before.isEmpty) _before = 'auto';
    await _serialize(() async {
      if (_valid(epoch)) {
        await bind.sessionPeerOption(
            sessionId: ffi.sessionId, name: ryadomCodecAutoKey, value: 'Y');
      }
    });
    if (!_valid(epoch)) return;
    _running = true;
    results.clear();
    _requireFullColor = bind.sessionGetToggleOptionSync(
        sessionId: ffi.sessionId, arg: kOptionI444);
    void listener() {
      if (_valid(epoch)) _sample();
    }

    ffi.qualityMonitorModel.addListener(listener);
    bool selected = false;
    try {
      final alternatives = jsonDecode(
          await bind.sessionAlternativeCodecs(sessionId: ffi.sessionId)) as Map;
      final candidates = [
        if (alternatives['vp8'] == true) 'vp8',
        'vp9',
        if (alternatives['h264'] == true) 'h264',
        if (alternatives['h265'] == true) 'h265',
        if (alternatives['av1'] == true) 'av1'
      ];
      final quality = await _qualitySignature();
      final display = _displaySignature();
      for (final candidate in candidates) {
        if (!_valid(epoch) || !_controls()) return;
        _trial = candidate;
        _samples.clear();
        _lastSampleMs = 0;
        _clock.reset();
        await _writeCodec(candidate, send: true, epoch: epoch);
        _clock.start();
        _status(
            'Проверка ${candidate.toUpperCase()}… Прокрутите документ или перемещайте окно.');
        while (_valid(epoch) &&
            _clock.elapsedMilliseconds < 6500 &&
            _samples.length < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!_valid(epoch) || !_controls()) return;
        _clock.stop();
        if (quality != await _qualitySignature() ||
            display != _displaySignature()) {
          _status('Изменились качество или экран. Повторите проверку кодеков.');
          return;
        }
        if (_samples.length >= 2) {
          double mean(double Function(CodecMeasurement) read) =>
              _samples.map(read).reduce((a, b) => a + b) / _samples.length;
          results.add(CodecMeasurement(candidate, mean((s) => s.fps),
              mean((s) => s.delayMs), mean((s) => s.bytesPerSecond),
              fullColor: _samples.every((s) => s.fullColor)));
        }
      }
      if (!_valid(epoch)) return;
      final best = chooseMeasuredCodec(results);
      await _writeCodec(best?.codec ?? _before, send: true, epoch: epoch);
      selected = true;
      _status(best == null
          ? 'Мало изменений изображения для сравнения. Сохранён прежний кодек. Нажмите для повторной проверки.'
          : 'Авто: ${best.codec.toUpperCase()} · ${best.fps.toStringAsFixed(0)} кадр/с · ${best.delayMs.toStringAsFixed(0)} мс');
    } catch (error) {
      if (_valid(epoch)) _status('Проверка кодеков не завершена: $error');
    } finally {
      ffi.qualityMonitorModel.removeListener(listener);
      if (_valid(epoch)) {
        if (!selected) await _writeCodec(_before, send: true, epoch: epoch);
        _running = false;
        notifyListeners();
      }
    }
  }

  String _displaySignature() =>
      '${ffi.ffiModel.pi.currentDisplay}:${ffi.ffiModel.pi.displays.map((d) => '${d.width}x${d.height}').join(',')}';
  Future<String> _qualitySignature() async =>
      '${await bind.sessionGetImageQuality(sessionId: ffi.sessionId)}:${await bind.sessionGetCustomImageQuality(sessionId: ffi.sessionId)}:${await bind.sessionGetOption(sessionId: ffi.sessionId, arg: "custom-fps")}:${bind.sessionGetToggleOptionSync(sessionId: ffi.sessionId, arg: kOptionI444)}';
  void _sample() {
    final elapsed = _clock.elapsedMilliseconds;
    if (!_running || elapsed < 1200 || elapsed - _lastSampleMs < 750) return;
    final data = ffi.qualityMonitorModel.data;
    if (!(data.codecFormat ?? '')
        .toLowerCase()
        .replaceAll('.', '')
        .contains(_trial)) return;
    final fpsParts = RegExp(r'\d+(?:\.\d+)?')
        .allMatches(data.fps ?? '')
        .map((m) => double.parse(m[0]!))
        .toList();
    final delay = double.tryParse(
        RegExp(r'\d+(?:\.\d+)?').firstMatch(data.delay ?? '')?[0] ?? '');
    final rate = double.tryParse(
        RegExp(r'\d+(?:\.\d+)?').firstMatch(data.speed ?? '')?[0] ?? '');
    if (fpsParts.isEmpty || delay == null || rate == null) return;
    final unit = (data.speed ?? '').toLowerCase();
    final bytes = rate *
        (unit.contains('mb')
            ? 1024 * 1024
            : unit.contains('kb')
                ? 1024
                : 1);
    final sample = CodecMeasurement(_trial,
        fpsParts.reduce((a, b) => a + b) / fpsParts.length, delay, bytes,
        fullColor: data.chroma == '4:4:4');
    if (sample.usable && (!_requireFullColor || sample.fullColor)) {
      _samples.add(sample);
      _lastSampleMs = elapsed;
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _disposed = true;
    if (_running) {
      final restore = _before;
      unawaited(_writes.then((_) async {
        final mode =
            await bind.mainGetPeerOption(id: ffi.id, key: ryadomCodecAutoKey);
        if (mode == 'Y') {
          await bind.mainSetPeerOption(
              id: ffi.id, key: kOptionCodecPreference, value: restore);
        }
      }).catchError((Object error) {
        debugPrint('Ryadom codec restore: $error');
      }));
    }
    super.dispose();
  }
}

class RyadomCodecButton extends StatelessWidget {
  const RyadomCodecButton({super.key, required this.ffi});
  final FFI ffi;
  @override
  Widget build(BuildContext context) {
    final controller = ryadomCodecController(ffi);
    return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => IconButton(
              tooltip: '${controller.status}\nРезультаты проверки кодеков',
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => AlertDialog(
                            title: const Text('Проверка кодеков'),
                            content: SingleChildScrollView(
                                child: SizedBox(
                                    width: 560,
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(controller.status),
                                          const SizedBox(height: 12),
                                          const Text(
                                              'Прокрутите документ или перемещайте окно. Проверка сравнивает FPS, задержку и трафик при выбранном качестве изображения; эталонное сравнение пикселей не выполняется.'),
                                          if (controller.results.isNotEmpty)
                                            DataTable(
                                                columns: const [
                                                  DataColumn(
                                                      label: Text('Кодек')),
                                                  DataColumn(
                                                      label: Text('FPS')),
                                                  DataColumn(label: Text('мс')),
                                                  DataColumn(
                                                      label: Text('КБ/с'))
                                                ],
                                                rows: controller.results
                                                    .map((r) => DataRow(cells: [
                                                          DataCell(Text(r.codec
                                                              .toUpperCase())),
                                                          DataCell(Text(r.fps
                                                              .toStringAsFixed(
                                                                  1))),
                                                          DataCell(Text(r
                                                              .delayMs
                                                              .toStringAsFixed(
                                                                  0))),
                                                          DataCell(Text(
                                                              (r.bytesPerSecond /
                                                                      1024)
                                                                  .toStringAsFixed(
                                                                      0)))
                                                        ]))
                                                    .toList()),
                                        ]))),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Закрыть')),
                              if (!controller.running)
                                FilledButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      unawaited(controller.select('auto'));
                                    },
                                    child: const Text('Проверить снова'))
                            ],
                          ))),
              icon: Icon(
                  controller.running
                      ? Icons.hourglass_top
                      : Icons.speed_outlined,
                  size: 20),
            ));
  }
}
