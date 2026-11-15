import 'package:flutter/material.dart';

const _ink = Color(0xff17233d);
const _blue = Color(0xff315cdb);
const _muted = Color(0xff46556b);

class RyadomComputer {
  const RyadomComputer({required this.id, required this.name, this.code = ''});
  final String id, name, code;
  String get number => RegExp(r'^[1-9][0-9]{8}$').hasMatch(code)
      ? code
      : RegExp(r'^[1-9][0-9]{8}$').hasMatch(id)
          ? id
          : '';
  String get displayedNumber => number.isEmpty
      ? 'ID ещё не сохранён'
      : '${number.substring(0, 3)} ${number.substring(3, 6)} ${number.substring(6)}';
}

class RyadomHomeContent extends StatelessWidget {
  const RyadomHomeContent(
      {super.key,
      required this.localId,
      required this.target,
      required this.computers,
      required this.onConnect,
      required this.onOpenComputer,
      required this.onCopy,
      required this.onSetPassword,
      this.onNetwork,
      this.onHelpP2P,
      this.relayConfigured = false,
      this.registrationMessage = '',
      this.registrationFailed = false,
      this.error = ''});
  final String localId, error, registrationMessage;
  final bool registrationFailed;
  final TextEditingController target;
  final List<RyadomComputer> computers;
  final VoidCallback onConnect, onCopy, onSetPassword;
  final VoidCallback? onNetwork;
  final VoidCallback? onHelpP2P;
  final bool relayConfigured;
  final ValueChanged<String> onOpenComputer;
  bool get ready =>
      RegExp(r'^([1-9][0-9]{8}|ryadom-[0-9a-f]{32})$').hasMatch(localId);
  bool get shortId => RegExp(r'^[1-9][0-9]{8}$').hasMatch(localId);
  String get displayedId => shortId
      ? '${localId.substring(0, 3)} ${localId.substring(3, 6)} ${localId.substring(6)}'
      : localId;

  Widget heading(IconData icon, String text) => Row(children: [
        Icon(icon, color: _blue, size: 22),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700, color: _ink)))
      ]);
  Widget panel(Widget child, bool compact) => DecoratedBox(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: EdgeInsets.all(compact ? 10 : 16), child: child));
  Widget share(bool compact) => panel(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading(Icons.screen_share_outlined, 'Дать доступ'),
        SizedBox(height: compact ? 8 : 12),
        Tooltip(
            message: registrationMessage,
            child: Text(
                registrationMessage.isEmpty
                    ? 'Ваш ID компьютера'
                    : registrationMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    color: registrationFailed ? Colors.red.shade700 : _muted))),
        const SizedBox(height: 6),
        SizedBox(
            height: shortId ? 30 : 24,
            child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SelectableText(
                    ready
                        ? displayedId
                        : registrationFailed
                            ? 'ID недоступен'
                            : 'Получаем ID…',
                    maxLines: 1,
                    style: TextStyle(
                        fontFamily: 'Segoe UI',
                        fontSize: shortId ? 22 : 15,
                        fontWeight: FontWeight.w700,
                        color: _ink)))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
              onPressed: ready ? onCopy : null,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Скопировать ID')),
          Tooltip(
              message: 'Постоянный пароль',
              child: TextButton(
                  onPressed: onSetPassword,
                  child: Text(compact ? 'Пароль' : 'Постоянный пароль'))),
        ]),
        if (!compact) ...[
          const SizedBox(height: 10),
          const Text(
              'Для разовой помощи нажмите «Разрешить», когда поступит запрос.',
              style: TextStyle(fontSize: 14, color: _muted))
        ]
      ]),
      compact);
  Widget join(bool compact) => panel(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading(Icons.near_me_outlined, 'Подключиться'),
        SizedBox(height: compact ? 8 : 12),
        TextField(
            controller: target,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
                hintText: 'ID удалённого компьютера',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder()),
            onSubmitted: (_) => onConnect()),
        const SizedBox(height: 10),
        FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Подключиться')),
        if (!compact) ...[
          const SizedBox(height: 10),
          const Text(
              'Введите пароль при подключении или дождитесь разрешения владельца.',
              style: TextStyle(fontSize: 14, color: _muted))
        ]
      ]),
      compact);
  Widget computerList() => computers.isEmpty
      ? const Align(
          alignment: Alignment.topLeft,
          child: Text('Компьютеры появятся здесь после первого подключения.',
              style: TextStyle(fontSize: 13, color: _muted)))
      : LayoutBuilder(builder: (context, box) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final columns =
              (box.maxWidth / (248 * scale)).floor().clamp(1, 4).toInt();
          return GridView.builder(
              padding: EdgeInsets.zero,
              itemCount: computers.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 38 * scale + 20,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6),
              itemBuilder: (_, index) {
                final computer = computers[index];
                return Tooltip(
                    message: computer.number.isEmpty
                        ? 'Подключитесь к сохранённому устройству: его числовой ID появится в истории после ответа новой версии Рядом.'
                        : 'Последний известный ID. Подключение проверяет сохранённую личность устройства, даже если номер изменился.',
                    child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onOpenComputer(computer.id),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                child: Row(children: [
                                  const Icon(Icons.computer_outlined,
                                      color: _blue, size: 19),
                                  const SizedBox(width: 9),
                                  Expanded(
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(computer.displayedNumber,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontFamily:
                                                    computer.number.isEmpty
                                                        ? null
                                                        : 'Consolas',
                                                fontSize:
                                                    computer.number.isEmpty
                                                        ? 13
                                                        : 17,
                                                fontWeight: FontWeight.w700,
                                                color: _ink)),
                                        Text(
                                            computer.name.isEmpty
                                                ? 'Сохранённый компьютер'
                                                : computer.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 13, color: _muted)),
                                      ])),
                                  const Icon(Icons.chevron_right,
                                      size: 16, color: _muted),
                                ])))));
              });
        });
  void showComputers(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: const Text('История подключений'),
              content: SizedBox(width: 900, height: 420, child: computerList()),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Закрыть'))
              ]));
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxHeight < 680 * scale;
        final short = constraints.maxHeight < 440 * scale;
        return ColoredBox(
            color: const Color(0xfff4f6fb),
            child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: short ? 12 : 18, vertical: short ? 8 : 18),
                child: Theme(
                    data: Theme.of(context)
                        .copyWith(visualDensity: VisualDensity.compact),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                    color: _blue,
                                    borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.devices_rounded,
                                    color: Colors.white, size: 22)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  const Text('Рядом',
                                      style: TextStyle(
                                          fontSize: 25,
                                          fontWeight: FontWeight.w800,
                                          color: _ink)),
                                  if (error.isNotEmpty)
                                    Tooltip(
                                        message: error,
                                        child: Text(error,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.red)))
                                  else if (!short)
                                    const Text(
                                        'Помощь близким. Где бы вы ни были.',
                                        style: TextStyle(
                                            fontSize: 14, color: _muted))
                                ])),
                            const Text('Тестовая сборка',
                                style: TextStyle(fontSize: 13, color: _muted)),
                            if (onNetwork != null)
                              IconButton(
                                  onPressed: onNetwork,
                                  tooltip: 'P2P и сеть',
                                  icon: const Icon(Icons.settings_ethernet,
                                      size: 20))
                          ]),
                          SizedBox(height: short ? 10 : 14),
                          IntrinsicHeight(
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                Expanded(child: share(compact)),
                                const SizedBox(width: 12),
                                Expanded(child: join(compact))
                              ])),
                          SizedBox(height: short ? 10 : 16),
                          Row(children: [
                            Expanded(
                                child: Text('История · ${computers.length}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: _ink))),
                            IconButton(
                                tooltip: 'Открыть всю историю',
                                onPressed: () => showComputers(context),
                                icon: const Icon(Icons.open_in_full, size: 17)),
                            if (onHelpP2P != null)
                              Expanded(
                                  flex: 2,
                                  child: Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                          onPressed: onHelpP2P,
                                          icon: const Icon(
                                              Icons.router_outlined,
                                              size: 16),
                                          label: const Text(
                                              'Помочь прямому подключению',
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis))))
                          ]),
                          const SizedBox(height: 8),
                          Expanded(child: computerList()),
                          if (!short) ...[
                            const SizedBox(height: 8),
                            Text(
                                relayConfigured
                                    ? 'Прямое соединение, при необходимости — личный TURN с ограниченной квотой.'
                                    : 'Прямое соединение. Личный TURN не настроен; возможен резерв другого участника.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, color: _muted))
                          ]
                        ]))));
      });
}
