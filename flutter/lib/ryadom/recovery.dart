import 'package:flutter/material.dart';
import 'dart:async';
import 'native_network_stub.dart' if (dart.library.io) 'native_network.dart';

final ryadomRecovery = ValueNotifier<Map<String, DateTime>>({});
void setRyadomRecovering(String id, int seconds) {
  ryadomRecovery.value = {
    ...ryadomRecovery.value,
    id: DateTime.now().add(Duration(seconds: seconds))
  };
}

void clearRyadomRecovery(String id) {
  final next = {...ryadomRecovery.value}..remove(id);
  ryadomRecovery.value = next;
}

class RyadomRecoveryNotice extends StatefulWidget {
  const RyadomRecoveryNotice({super.key, required this.session});
  final String session;
  @override
  State<RyadomRecoveryNotice> createState() => _RecoveryNoticeState();
}

class _RecoveryNoticeState extends State<RyadomRecoveryNotice> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, DateTime>>(
          valueListenable: ryadomRecovery,
          builder: (_, states, __) {
            final until = states[widget.session];
            if (until == null) return const SizedBox.shrink();
            final seconds =
                until.difference(DateTime.now()).inSeconds.clamp(0, 300);
            return Tooltip(
                message:
                    'Разрешение текущего сеанса сохраняется до 5 минут. Можно завершить подключение кнопкой закрытия.',
                child: Text(
                    'Восстанавливаем связь… ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600)));
          });
}

class RyadomRecoveryOwner extends StatefulWidget {
  const RyadomRecoveryOwner(
      {super.key, required this.connection, required this.onEnded});
  final int connection;
  final VoidCallback onEnded;
  @override
  State<RyadomRecoveryOwner> createState() => _OwnerRecoveryState();
}

class _OwnerRecoveryState extends State<RyadomRecoveryOwner> {
  Timer? timer;
  Map<String, dynamic>? session;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    poll();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
  }

  Future<void> poll() async {
    if (loading) return;
    loading = true;
    try {
      final state = await ryadomNetworkRequest({'action': 'resume-host-state'});
      final matches = (state['sessions'] as List? ?? [])
          .where((s) => s['connection'] == widget.connection);
      if (mounted)
        setState(() => session =
            matches.isEmpty ? null : Map<String, dynamic>.from(matches.first));
    } catch (_) {
    } finally {
      loading = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
            session == null
                ? 'Разрешение на восстановление завершено'
                : 'Связь потеряна. Ожидаем восстановления: ${session!['remaining']} с',
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        FilledButton(
            onPressed: () async {
              if (session != null)
                await ryadomNetworkRequest(
                    {'action': 'resume-host-revoke', 'id': session!['id']});
              if (mounted) widget.onEnded();
            },
            child: const Text('Завершить доступ')),
      ]);
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
