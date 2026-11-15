import 'dart:async';
import 'package:flutter/material.dart';
import 'native_network_stub.dart' if (dart.library.io) 'native_network.dart';

Future<void> showRyadomP2P(BuildContext context,
        {bool enable = false, String? session}) =>
    showDialog<void>(
        context: context,
        builder: (_) => _P2PPanel(enable: enable, session: session));

class RyadomP2PButton extends StatefulWidget {
  const RyadomP2PButton({super.key, required this.session});
  final String session;
  @override
  State<RyadomP2PButton> createState() => _P2PButtonState();
}

class _P2PButtonState extends State<RyadomP2PButton> {
  Timer? timer;
  bool available = false, pending = false;
  @override
  void initState() {
    super.initState();
    poll();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  Future<void> poll() async {
    if (pending) return;
    pending = true;
    try {
      final state = await ryadomNetworkRequest(
          {'action': 'p2p-state', 'session': widget.session});
      if (mounted) setState(() => available = state['available'] == true);
    } catch (_) {
      if (mounted) setState(() => available = false);
    } finally {
      pending = false;
    }
  }

  @override
  Widget build(BuildContext context) => available
      ? TextButton.icon(
          onPressed: () async {
            await ryadomNetworkRequest(
                {'action': 'p2p-switch', 'session': widget.session});
            await poll();
          },
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Перейти на P2P'))
      : IconButton(
          tooltip: 'P2P и сеть',
          icon: const Icon(Icons.router_outlined, size: 20),
          onPressed: () => showRyadomP2P(context, session: widget.session));
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}

class _P2PPanel extends StatefulWidget {
  const _P2PPanel({required this.enable, this.session});
  final bool enable;
  final String? session;
  @override
  State<_P2PPanel> createState() => _P2PState();
}

class _P2PState extends State<_P2PPanel> {
  Map<String, dynamic> state = {}, peer = {};
  String message = '', failure = '';
  bool pending = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    if (widget.enable) {
      setEnabled(true);
    } else {
      poll();
    }
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  Future<void> poll() async {
    if (pending) return;
    pending = true;
    try {
      final next = await ryadomNetworkRequest({'action': 'helper-state'});
      final target = widget.session == null
          ? <String, dynamic>{}
          : await ryadomNetworkRequest(
              {'action': 'p2p-state', 'session': widget.session});
      if (mounted)
        setState(() {
          state = next;
          peer = target;
          failure = '';
        });
    } catch (_) {
      if (mounted) setState(() => failure = 'Нет связи с локальной службой Рядом. Если программа установлена, откройте её через меню «Пуск». Проверка повторится автоматически.');
    } finally {
      pending = false;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (pending) return;
    setState(() => pending = true);
    try {
      final result = await ryadomNetworkRequest(
          {'action': 'helper-set', 'enabled': value});
      if (mounted)
        setState(() => message = result['message']?.toString() ?? '');
    } catch (_) {
      if (mounted) setState(() => failure = 'Не удалось передать настройку локальной службе Рядом. Откройте установленную программу и повторите попытку.');
    } finally {
      pending = false;
    }
    await poll();
  }

  Future<void> action(String action) async {
    try {
      await ryadomNetworkRequest({'action': action, 'session': widget.session});
      await poll();
    } catch (_) {
      if (mounted) setState(() => failure = 'Нет связи с ядром сеанса Рядом. Дождитесь восстановления связи и повторите попытку.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Прямое подключение P2P'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(failure.isNotEmpty
                        ? failure
                        : state['message']?.toString() ?? 'Проверяем состояние…'),
                    if (state['detail'] != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(state['detail'].toString())),
                    if (state['protocol'] != null)
                      Text(
                          'Роутер: ${state['protocol']}, UDP-порт ${state['port']}'),
                    if (state['leaseSeconds'] != null)
                      Text(
                          'Аренда: ${state['leaseSeconds']} с. Продлевается автоматически без переподключения.'),
                    if (state['stun'] is List)
                      for (final server in state['stun'])
                        Text(
                            '${server['server']}: ${server['ok'] == true ? 'UDP отвечает' : 'ответа нет'}'),
                    if (state['ipv6'] != null)
                      Text(
                          'IPv6: ${state['ipv6'] == true ? 'доступен на ПК' : 'прямой маршрут не обнаружен'}'),
                    if (message.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(message)),
                    const SizedBox(height: 12),
                    const Text(
                        'Режим сохраняется на этом ПК. Программа сама поддерживает временный порт, пока принимает подключения. Для правила брандмауэра могут понадобиться права администратора.'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                        onPressed: pending ? null : () => setEnabled(true),
                        icon: const Icon(Icons.router_outlined),
                        label: const Text('Помочь прямому подключению')),
                    if (state['enabled'] == true)
                      TextButton(
                          onPressed: pending ? null : () => setEnabled(false),
                          child: const Text('Выключить помощник P2P')),
                    if (widget.session != null) ...[
                      const Divider(),
                      Text(peer['message']?.toString() ??
                          'Проверяется только настоящий прямой канал со вторым ПК.'),
                      TextButton(
                          onPressed: peer['checking'] == true
                              ? null
                              : () => action('p2p-check'),
                          child: const Text('Проверить P2P')),
                      if (peer['available'] == true)
                        FilledButton(
                            onPressed: () => action('p2p-switch'),
                            child: const Text('Перейти на P2P')),
                    ],
                    TextButton(
                        onPressed: () => showRyadomNetworkSettings(context),
                        child: const Text('Резервный TURN — дополнительно')),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'))
          ]);
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
