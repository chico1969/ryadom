import 'package:flutter/material.dart';
import 'native_network_stub.dart' if (dart.library.io) 'native_network.dart';

class RyadomAutostartOption extends StatelessWidget {
  const RyadomAutostartOption(
      {super.key, this.value = true, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text('Запускать вместе с Windows'),
      value: value,
      onChanged: onChanged == null ? null : (value) => onChanged!(value == true));
}

class RyadomAutostartSetting extends StatefulWidget {
  const RyadomAutostartSetting({super.key});
  @override
  State<RyadomAutostartSetting> createState() => _AutostartState();
}

class _AutostartState extends State<RyadomAutostartSetting> {
  bool pending = true, enabled = true, available = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  void apply(Map<String, dynamic> value) {
    enabled = value['enabled'] == true;
    available = value['available'] == true;
  }

  Future<void> load() async {
    try {
      final state = await ryadomNetworkRequest({'action': 'autostart-get'});
      if (mounted) setState(() => apply(state));
    } catch (_) {
      if (mounted) setState(() => error = 'Не удалось прочитать настройку Windows.');
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  Future<void> change(bool value) async {
    setState(() {pending = true; error = '';});
    try {
      final state = await ryadomNetworkRequest(
          {'action': 'autostart-set', 'enabled': value});
      if (mounted) setState(() => apply(state));
    } catch (failure) {
      if (mounted) {
        setState(() => error = failure.toString().replaceFirst('Bad state: ', ''));
        await load();
      }
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RyadomAutostartOption(
            value: enabled,
            onChanged: pending || !available ? null : change),
        if (pending) const LinearProgressIndicator(),
        Text(available
            ? 'Управляет службой и значком в трее при запуске Windows. Текущие подключения продолжат работать. Windows может запросить права администратора.'
            : 'Для автозапуска установите Рядом через Setup.'),
        if (error.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]);
}
