import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

const ryadomPrivacyPolicyUrl =
    'https://github.com/chico1969/ryadom/blob/ryadom/PRIVACY.md';

String ryadomInstallNetworkOption(bool enabled) => enabled
    ? ' --ryadom-background-network'
    : ' --ryadom-no-background-network';

class RyadomInstallPrivacy extends StatelessWidget {
  const RyadomInstallPrivacy(
      {super.key, required this.backgroundNetwork, required this.onChanged});

  final bool backgroundNetwork;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            controlAffinity: ListTileControlAffinity.leading,
            title:
                const Text('Разрешить фоновую связь для входящих подключений'),
            value: backgroundNetwork,
            onChanged: onChanged == null
                ? null
                : (value) => onChanged!(value == true)),
        const Text(
            'Служба поиска alwaysdata получает ID, IP-адреса и сведения для '
            'соединения. STUN ищет прямой маршрут; настроенный TURN при '
            'необходимости передаёт зашифрованный сеанс. После установки без '
            'галочки нет фонового входящего доступа. Подключение к другому ПК '
            'и «Включить приём» используют сеть.'),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                          title: const Text('Конфиденциальность «Рядом»'),
                          content: const SizedBox(
                              width: 560,
                              child: SingleChildScrollView(
                                  child: Text(_privacyPolicy,
                                      style: TextStyle(height: 1.4)))),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Закрыть'))
                          ])),
              icon: const Icon(Icons.privacy_tip_outlined, size: 18),
              label: const Text('Как используются данные')),
          TextButton.icon(
              onPressed: () => launchUrlString(ryadomPrivacyPolicyUrl),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Политика на GitHub'))
        ])
      ]));
}

class RyadomInstallFooter extends StatelessWidget {
  const RyadomInstallFooter(
      {super.key,
      required this.onInstall,
      required this.onCancel,
      this.showProgress = false,
      this.showRunWithoutInstall = false,
      this.onRunWithoutInstall});

  final VoidCallback? onInstall;
  final VoidCallback? onCancel;
  final bool showProgress;
  final bool showRunWithoutInstall;
  final VoidCallback? onRunWithoutInstall;

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border:
              Border(top: BorderSide(color: Theme.of(context).dividerColor))),
      child: SafeArea(
          top: false,
          minimum: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (showProgress)
              const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator()),
            Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Отмена')),
                  ElevatedButton.icon(
                      onPressed: onInstall,
                      icon: const Icon(Icons.done_rounded, size: 16),
                      label: const Text('Принять и установить')),
                  if (showRunWithoutInstall)
                    OutlinedButton.icon(
                        onPressed: onRunWithoutInstall,
                        icon: const Icon(Icons.screen_share_outlined, size: 16),
                        label: const Text('Запустить без установки'))
                ]))
          ])));
}

const _privacyPolicy =
    '''«Рядом» — приложение удалённой помощи. ID служит для поиска компьютера. Доступ к рабочему столу требует разрешения владельца или настроенной аутентификации.

При разрешённой фоновой связи приложение регистрирует этот ПК в службе поиска на alwaysdata. Служба получает IP-адреса, ID, открытый ключ устройства и сведения согласования соединения, включая локальные и публичные сетевые адреса. Служба поиска не передаёт экран, файлы или команды терминала. Провайдер может сохранять служебные журналы.

STUN помогает найти прямой маршрут и получает сетевые запросы с IP-адресом. Настроенный TURN может передавать зашифрованный трафик сеанса и видит адреса, время и объём передачи. Публичная сборка не содержит семейных данных доступа к TURN. Политики провайдеров и подробности опубликованы в полной политике на GitHub.

Экран, звук, ввод, буфер обмена, файлы, чат и команды передаются в рамках разрешённого сеанса при использовании соответствующих функций. Запись сохраняется на устройстве участника, который её начал, и может содержать личные данные.

История подключений, настройки, данные доступа и журналы хранятся локально. Облачной синхронизации адресной книги и рекламной аналитики нет. При включении помощника P2P приложение обращается к роутеру за временным UDP-пробросом; для правила брандмауэра Windows может запросить права администратора.

Снятая галочка фоновой связи отключает регистрацию установленного приложения для входящих подключений. Явное исходящее подключение или включение приёма снова использует сеть. Автозапуск — отдельная настройка. Для удаления приложения используйте «Установленные приложения» Windows; сохранённые настройки, записи и полученные файлы могут потребовать отдельного удаления. Не публикуйте пароли и личные журналы в открытых обращениях.''';
