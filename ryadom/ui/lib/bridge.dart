import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as util;

class Engine {
  final Object namespace = util.getProperty(html.window, 'RyadomEngine');
  late final Object vault =
      util.callConstructor(util.getProperty(namespace, 'Vault'), []);
  Object? session;
  bool get relayAllowed => false;
  Future<dynamic> _future(dynamic value) => util.promiseToFuture(value);
  Future<List<dynamic>> computers() async {
    final rows = await _future(util.callMethod(vault, 'computers', []));
    return (jsonDecode(util.callMethod(
        util.getProperty(html.window, 'JSON'), 'stringify', [rows])) as List);
  }

  Future<void> forget(String id) async {
    await _future(util.callMethod(vault, 'remove', [id]));
  }

  Future<dynamic> _turnServersRaw() =>
      _future(util.callMethod(vault, 'turnServers', []));
  Future<List<dynamic>?> turnServers() async {
    final servers = await _turnServersRaw();
    return servers == null
        ? null
        : jsonDecode(util.callMethod(
                util.getProperty(html.window, 'JSON'), 'stringify', [servers]))
            as List;
  }

  Future<void> saveTurnServers(String raw) async {
    await _future(util.callMethod(vault, 'saveTurnServers', [raw]));
  }

  Future<void> create(String id, void Function(String, dynamic) event) async {
    final resolved =
        await _future(util.callMethod(namespace, 'resolvePeer', [id]));
    final servers = await _turnServersRaw();
    session = util.callConstructor(util.getProperty(namespace, 'Session'),
        servers == null ? [resolved] : [resolved, servers]);
    if (RegExp(r'^[1-9][0-9]{8}$').hasMatch(id))
      util.setProperty(session!, 'displayCode', id);
    for (final name in [
      'status',
      'error',
      'warning',
      'password',
      'connected',
      'control',
      'chat',
      'clipboard',
      'directory',
      'overwrite',
      'progress',
      'fileDone',
      'terminalText',
      'closed',
      'direct',
      'transport',
      'codecTest',
      'recovering',
      'p2p'
    ]) {
      util.callMethod(session!, 'addEventListener', [
        name,
        js.allowInterop((dynamic e) {
          final raw = util.getProperty(e, 'detail');
          final detail = raw is String ||
                  raw is num ||
                  raw is bool ||
                  raw == null
              ? raw
              : jsonDecode(util.callMethod(
                  util.getProperty(html.window, 'JSON'), 'stringify', [raw]));
          event(name, detail);
        })
      ]);
    }
  }

  Future<dynamic> call(String method, [List<dynamic> args = const []]) =>
      _future(util.callMethod(session!, method, args));
  Future<dynamic> media(String method) =>
      _future(util.callMethod(util.getProperty(session!, 'media'), method, []));
  void mount(html.Element element) {
    if (session != null) util.callMethod(session!, 'mount', [element]);
  }

  Future<void> mountTerminal(html.Element element) async {
    await _future(util.callMethod(session!, 'mountTerminal', [element]));
  }

  void clipboard(bool allow) {
    if (session != null) util.setProperty(session!, 'clipboardAllowed', allow);
  }
}
