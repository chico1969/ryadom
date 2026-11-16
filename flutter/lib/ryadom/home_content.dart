import 'package:flutter/material.dart';

const _ink = Color(0xff17233d);
const _blue = Color(0xff315cdb);
const _muted = Color(0xff46556b);

class _HomeColors {
  _HomeColors(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get background =>
      dark ? const Color(0xff171e2b) : const Color(0xfff4f6fb);
  Color get surface => dark ? const Color(0xff242e40) : Colors.white;
  Color get ink => dark ? const Color(0xffedf2f8) : _ink;
  Color get muted => dark ? const Color(0xffbbc7d8) : _muted;
  Color get accent => dark ? const Color(0xff9ab4ff) : _blue;
  Color get error => dark ? const Color(0xffffa8a2) : Colors.red.shade700;
}

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
      this.onSettings,
      this.onNetwork,
      this.onHelpP2P,
      this.onStartReceiving,
      this.relayConfigured = false,
      this.registrationMessage = '',
      this.registrationFailed = false,
      this.error = ''});
  final String localId, error, registrationMessage;
  final bool registrationFailed;
  final TextEditingController target;
  final List<RyadomComputer> computers;
  final VoidCallback onConnect, onCopy, onSetPassword;
  final VoidCallback? onSettings, onNetwork;
  final VoidCallback? onHelpP2P;
  final VoidCallback? onStartReceiving;
  final bool relayConfigured;
  final ValueChanged<String> onOpenComputer;
  bool get ready =>
      RegExp(r'^([1-9][0-9]{8}|ryadom-[0-9a-f]{32})$').hasMatch(localId);
  bool get shortId => RegExp(r'^[1-9][0-9]{8}$').hasMatch(localId);
  String get displayedId => shortId
      ? '${localId.substring(0, 3)} ${localId.substring(3, 6)} ${localId.substring(6)}'
      : localId;

  Widget heading(BuildContext context, IconData icon, String text) =>
      Row(children: [
        Icon(icon, color: _HomeColors(context).accent, size: 22),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _HomeColors(context).ink)))
      ]);
  Widget panel(BuildContext context, Widget child, bool compact) => DecoratedBox(
      decoration: BoxDecoration(
          color: _HomeColors(context).surface,
          borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: EdgeInsets.all(compact ? 10 : 16), child: child));
  Widget share(BuildContext context, bool compact) => panel(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading(context, Icons.screen_share_outlined, 'Дать доступ'),
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
                    color: registrationFailed
                        ? _HomeColors(context).error
                        : _HomeColors(context).muted))),
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
                        color: _HomeColors(context).ink)))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (onStartReceiving != null)
            OutlinedButton.icon(
                onPressed: onStartReceiving,
                icon: const Icon(Icons.play_arrow, size: 15),
                label: const Text('Включить приём'))
          else
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
          Text(
              'Для разовой помощи нажмите «Разрешить», когда поступит запрос.',
              style: TextStyle(fontSize: 14, color: _HomeColors(context).muted))
        ]
      ]),
      compact);
  Widget join(BuildContext context, bool compact) => panel(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        heading(context, Icons.near_me_outlined, 'Подключиться'),
        SizedBox(height: compact ? 8 : 12),
        TextField(
            controller: target,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _HomeColors(context).ink),
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
          Text(
              'Введите пароль при подключении или дождитесь разрешения владельца.',
              style: TextStyle(fontSize: 14, color: _HomeColors(context).muted))
        ]
      ]),
      compact);
  Widget computerList(BuildContext context) => computers.isEmpty
      ? Align(
          alignment: Alignment.topLeft,
          child: Text('Компьютеры появятся здесь после первого подключения.',
              style:
                  TextStyle(fontSize: 13, color: _HomeColors(context).muted)))
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
                        color: _HomeColors(context).surface,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onOpenComputer(computer.id),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                child: Row(children: [
                                  Icon(Icons.computer_outlined,
                                      color: _HomeColors(context).accent,
                                      size: 19),
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
                                                color:
                                                    _HomeColors(context).ink)),
                                        Text(
                                            computer.name.isEmpty
                                                ? 'Сохранённый компьютер'
                                                : computer.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: _HomeColors(context)
                                                    .muted)),
                                      ])),
                                  Icon(Icons.chevron_right,
                                      size: 16,
                                      color: _HomeColors(context).muted),
                                ])))));
              });
        });
  void showComputers(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: const Text('История подключений'),
              content: SizedBox(
                  width: 900, height: 420, child: computerList(context)),
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
        final colors = _HomeColors(context);
        final base = Theme.of(context);
        return ColoredBox(
            color: colors.background,
            child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: short ? 12 : 18, vertical: short ? 8 : 18),
                child: Theme(
                    data: base.copyWith(
                        visualDensity: VisualDensity.compact,
                        iconTheme: base.iconTheme.copyWith(color: colors.ink),
                        textButtonTheme: colors.dark
                            ? TextButtonThemeData(
                                style: TextButton.styleFrom(
                                    foregroundColor: colors.accent))
                            : base.textButtonTheme,
                        outlinedButtonTheme: colors.dark
                            ? OutlinedButtonThemeData(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: colors.accent,
                                    side: const BorderSide(
                                        color: Color(0xff63738c))))
                            : base.outlinedButtonTheme,
                        filledButtonTheme: colors.dark
                            ? FilledButtonThemeData(
                                style: FilledButton.styleFrom(
                                    backgroundColor: _blue,
                                    foregroundColor: Colors.white))
                            : base.filledButtonTheme,
                        inputDecorationTheme: colors.dark
                            ? base.inputDecorationTheme.copyWith(
                                filled: true,
                                fillColor: const Color(0xff171e2b),
                                hintStyle: base.inputDecorationTheme.hintStyle
                                        ?.copyWith(color: colors.muted) ??
                                    TextStyle(color: colors.muted),
                                enabledBorder: const OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Color(0xff63738c))),
                                focusedBorder:
                                    OutlineInputBorder(borderSide: BorderSide(color: colors.accent, width: 2)))
                            : base.inputDecorationTheme),
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
                                  Text('Рядом',
                                      style: TextStyle(
                                          fontSize: 25,
                                          fontWeight: FontWeight.w800,
                                          color: colors.ink)),
                                  if (error.isNotEmpty)
                                    Tooltip(
                                        message: error,
                                        child: Text(error,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 14,
                                                color: colors.dark
                                                    ? colors.error
                                                    : Colors.red)))
                                  else if (!short)
                                    Text(
                                        'Помощь близким. Где бы вы ни были.',
                                        style: TextStyle(
                                            fontSize: 14, color: colors.muted))
                                ])),
                            if (onSettings != null)
                              Tooltip(
                                  message: 'Настройки',
                                  child: TextButton.icon(
                                      onPressed: onSettings,
                                      style: TextButton.styleFrom(
                                          foregroundColor: colors.accent),
                                      icon: const Icon(Icons.settings_outlined,
                                          size: 20),
                                      label: const Text('Настройки'))),
                            if (onNetwork != null)
                              Tooltip(
                                  message: 'Настройки подключения',
                                  child: TextButton.icon(
                                      onPressed: onNetwork,
                                      style: TextButton.styleFrom(
                                          foregroundColor: colors.accent),
                                      icon: const Icon(Icons.settings_ethernet,
                                          size: 20),
                                      label: const Text('P2P / TURN')))
                          ]),
                          SizedBox(height: short ? 10 : 14),
                          IntrinsicHeight(
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                Expanded(child: share(context, compact)),
                                const SizedBox(width: 12),
                                Expanded(child: join(context, compact))
                              ])),
                          SizedBox(height: short ? 10 : 16),
                          Row(children: [
                            Expanded(
                                child: Text('История · ${computers.length}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: colors.ink))),
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
                          Expanded(child: computerList(context)),
                          if (!short) ...[
                            const SizedBox(height: 8),
                            Text(
                                relayConfigured
                                    ? 'Прямое соединение, при необходимости — личный TURN с ограниченной квотой.'
                                    : 'Прямое соединение. Личный TURN не настроен; возможен резерв другого участника.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13, color: colors.muted))
                          ]
                        ]))));
      });
}
