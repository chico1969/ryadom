import 'package:flutter/material.dart';

class RyadomSessionHints extends StatelessWidget {
  const RyadomSessionHints({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TooltipTheme(
      data: TooltipTheme.of(context).copyWith(
          waitDuration: Duration.zero,
          exitDuration: const Duration(milliseconds: 80),
          showDuration: const Duration(seconds: 8)),
      child: child);
}

String ryadomInputSourceLabel(String source) => source == 'Input source 1'
    ? 'Системный ввод (основной)'
    : 'Ввод через окно (совместимость)';
String ryadomInputSourceHelp(String source) => source == 'Input source 1'
    ? 'Считывает клавиши средствами Windows. Основной вариант для передачи сочетаний клавиш удалённому ПК.'
    : 'Считывает клавиши, которые получает окно Рядом. Используйте при проблемах с системным вводом. Часть сочетаний Windows может обрабатываться на вашем ПК.';

String ryadomKeyboardLabel(String mode) => switch (mode) {
      'map' => 'Физические клавиши',
      'translate' => 'Ввод текста',
      _ => 'Режим совместимости',
    };
String ryadomKeyboardHelp(String mode) => switch (mode) {
      'map' =>
        'Передаёт физические клавиши. Результат зависит от раскладки на удалённом ПК.',
      'translate' =>
        'Передаёт набираемые символы с учётом вашей раскладки. Экспериментальный режим.',
      _ =>
        'Прежний способ передачи клавиш. Используйте, если основной режим работает неправильно.',
    };

const ryadomViewOnlyLabel = 'Просмотр с указкой';
const ryadomViewOnlyHelp =
    'Вы показываете оранжевым указателем на удалённом экране. Нажатия мыши только выделяют место; они не нажимают кнопки программ. Ввод текста и управление отключены.';
const ryadomClipboardAction = 'Напечатать текст из моего буфера…';
const ryadomClipboardHelp =
    'Разовая команда: отправить текст из вашего буфера в активное поле удалённого приложения как текстовый ввод. Для обычной вставки используйте Ctrl+V.';
