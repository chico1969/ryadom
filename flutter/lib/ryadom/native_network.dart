import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

typedef _Native = Int32 Function(
    Pointer<Uint8>, Uint32, Pointer<Uint8>, Uint32);
typedef _Request = int Function(Pointer<Uint8>, int, Pointer<Uint8>, int);

Map<String, dynamic> _request(Map<String, dynamic> value) {
  final request = DynamicLibrary.open(path.join(
          path.dirname(Platform.resolvedExecutable), 'librustdesk.dll'))
      .lookupFunction<_Native, _Request>('ryadom_request_v1');
  final raw = utf8.encode(jsonEncode(value));
  final input = calloc<Uint8>(raw.length);
  final output = calloc<Uint8>(65536);
  try {
    input.asTypedList(raw.length).setAll(0, raw);
    final count = request(input, raw.length, output, 65536);
    if (count < 0) throw StateError('Не удалось открыть настройку TURN');
    final result = jsonDecode(utf8.decode(output.asTypedList(count)))
        as Map<String, dynamic>;
    if (result['error'] != null) throw StateError(result['error']);
    return result;
  } finally {
    calloc.free(input);
    calloc.free(output);
  }
}

Future<Map<String,dynamic>> ryadomNetworkRequest(Map<String,dynamic> value) => Isolate.run(()=>_request(value));

bool ownerTurnConfigured() =>
    _request({'action': 'network-get'})['configured'] == true;

Future<Map<String, dynamic>> ryadomRegistrationState() =>
    Isolate.run(() => _request({'action': 'registration-state'}));

bool ryadomSessionControls(String session) {
  final state = _request({'action': 'local-state', 'session': session});
  return state['you'] != null && state['you'] == state['holder'];
}

Future<String> resolveRyadomPeer(String value) async {
  if (RegExp(r'^ryadom-[0-9a-f]{32}$').hasMatch(value)) return value;
  if (!RegExp(r'^[1-9][0-9]{8}$').hasMatch(value)) {
    throw StateError('Введите 9 цифр ID компьютера');
  }
  final random = Random.secure();
  final nonce = List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  final client = 'ryadom-lookup-$nonce';
  final base = Uri.parse(_request({'action': 'signal-url'})['url'] as String);
  final socket = await WebSocket.connect(base.replace(queryParameters: {
    ...base.queryParameters,
    'id': client,
    'token': nonce,
    'version': '1.5.5'
  }).toString())
      .timeout(const Duration(seconds: 15));
  final messages = StreamIterator<dynamic>(socket);
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  try {
    while (DateTime.now().isBefore(deadline) &&
        await messages.moveNext().timeout(const Duration(seconds: 10))) {
      final raw = messages.current;
      if (raw is! String || raw.length > 131072) {
        throw StateError('Неверное сообщение службы поиска');
      }
      final message = jsonDecode(raw) as Map;
      if (message['type'] == 'OPEN') {
        socket.add(jsonEncode({
          'type': 'OFFER',
          'dst': 'ryadom-code-$value',
          'payload': {
            'type': 'data',
            'connectionId': 'lookup_$nonce',
            'label': 'bootstrap',
            'serialization': 'raw',
            'reliable': true,
            'sdp': {'type': 'offer', 'sdp': 'v=0\r\n'},
            'metadata': {'ryadomLookup': 1, 'nonce': nonce}
          }
        }));
      } else if (message['type'] == 'ANSWER' &&
          message['src'] == 'ryadom-code-$value' &&
          message['payload']?['connectionId'] == 'lookup_$nonce') {
        return _request({
          'action': 'verify-code',
          'code': value,
          'nonce': nonce,
          'client': client,
          'reply': message['payload']['metadata']
        })['id'] as String;
      } else if (['EXPIRE', 'ERROR', 'ID-TAKEN'].contains(message['type'])) {
        throw StateError(
            'Компьютер с этим ID недоступен. Проверьте цифры и запуск Рядом.');
      }
    }
    throw StateError('Не удалось найти компьютер по короткому ID');
  } finally {
    await messages.cancel();
    await socket.close();
  }
}

Future<void> showRyadomNetworkSettings(BuildContext context) async {
  final network = _request({'action': 'network-get'});
  final shared = network['sharedTestBuild'] == true;
  final urls = TextEditingController(
      text:
          'turn:free.expressturn.com:3478\nturn:free.expressturn.com:3478?transport=tcp');
  final username = TextEditingController();
  final credential = TextEditingController();
  String error = '';
  try {
    await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setState) {
              void save(List<Map<String, dynamic>> servers) {
                try {
                  _request({'action': 'network-set', 'servers': servers});
                  Navigator.pop(context);
                } catch (e) {
                  setState(() => error = e.toString());
                }
              }

              return AlertDialog(
                  title: const Text('Резервное соединение TURN'),
                  content: SizedBox(
                      width: 500,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(shared
                            ? 'Семейный TURN уже встроен: на другом ПК ничего вводить не нужно. Общий пароль можно извлечь из EXE. Здесь можно указать свой сервер. После изменения перезапустите приложение.'
                            : 'Личные данные защищаются учётной записью Windows на этом ПК. Не вводите API-ключ аккаунта. После изменения перезапустите приложение.'),
                        const SizedBox(height: 12),
                        ExpansionTile(
                            title: const Text('Другой сервер (дополнительно)'),
                            children: [
                              TextField(
                                  controller: urls,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                      labelText: 'Адреса TURN'))
                            ]),
                        TextField(
                            controller: username,
                            decoration: const InputDecoration(
                                labelText: 'Имя пользователя TURN')),
                        TextField(
                            controller: credential,
                            obscureText: true,
                            decoration: const InputDecoration(
                                labelText: 'Пароль TURN')),
                        if (error.isNotEmpty)
                          Text(error, style: const TextStyle(color: Colors.red))
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена')),
                    TextButton(
                        onPressed: () => save([]),
                        child: const Text('Отключить TURN')),
                    FilledButton(
                        onPressed: () => save([
                              {
                                'urls': urls.text
                                    .split(RegExp(r'\s+'))
                                    .where((value) => value.isNotEmpty)
                                    .toList(),
                                'username': username.text.trim(),
                                'credential': credential.text
                              }
                            ]),
                        child: const Text('Сохранить на этом ПК'))
                  ]);
            }));
  } finally {
    urls.dispose();
    username.dispose();
    credential.dispose();
  }
}
