import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'bridge.dart';

void main() => runApp(const RyadomApp());
const ink = Color(0xff17233d);
const blue = Color(0xff315cdb);

class RyadomApp extends StatelessWidget {
  const RyadomApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Рядом',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true,
          tooltipTheme: const TooltipThemeData(waitDuration: Duration.zero),
          colorScheme: ColorScheme.fromSeed(seedColor: blue),
          scaffoldBackgroundColor: const Color(0xfff4f6fb),
          fontFamily: 'Segoe UI',
          fontFamilyFallback: const ['NotoSans', 'Arial'],
          textTheme: const TextTheme(
              bodyMedium: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: ink),
              bodySmall: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500, color: ink),
              labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          inputDecorationTheme: InputDecorationTheme(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white),
          cardTheme: CardTheme(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22)))),
      home: const Workspace());
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  final engine = Engine();
  final id = TextEditingController(),
      password = TextEditingController(),
      chat = TextEditingController(),
      path = TextEditingController(text: ''),
      terminal = TextEditingController();
  List<dynamic> saved = [], displays = [], files = [], participants = [];
  final messages = <String>[];
  String status = 'Помощь близким. Где бы вы ни были.',
      error = '',
      terminalText = '',
      clipboard = '';
  bool busy = false,
      active = false,
      remember = false,
      recording = false,
      allowClipboard = false,
      controls = false,
      terminalVisible = false;
  bool passwordDialogOpen = false;
  bool localRelay = false;
  bool sessionToolbarVisible = true;
  bool p2pAvailable = false, p2pChecking = false, recovering = false;
  String transport = '';
  String codecStatus = 'Авто — проверка кодеков';
  List<dynamic> codecResults = [];
  int monitor = 0, tab = 0, you = 0, holder = 0;
  html.DivElement? surface;
  @override
  void initState() {
    super.initState();
    ui.platformViewRegistry.registerViewFactory('ryadom-screen', (_) {
      surface = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%';
      engine.mount(surface!);
      return surface!;
    });
    ui.platformViewRegistry.registerViewFactory('ryadom-terminal', (_) {
      final element = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%';
      unawaited(engine.mountTerminal(element));
      return element;
    });
    ui.platformViewRegistry.registerViewFactory('ryadom-file-drop', (_) {
      final drop = html.DivElement()
        ..text = 'Перетащите сюда файлы для отправки'
        ..style.cssText =
            'height:100%;box-sizing:border-box;border:2px dashed #b7c6ed;border-radius:12px;display:flex;align-items:center;justify-content:center;text-align:center;color:#315cdb;font:14px sans-serif;';
      drop.onDragOver.listen((event) => event.preventDefault());
      drop.onDrop.listen((event) {
        event.preventDefault();
        final items = event.dataTransfer.files;
        if (controls && items != null) unawaited(uploadFiles(items));
      });
      return drop;
    });
    final invite = Uri.base.fragment.replaceFirst('id=', '');
    if (RegExp(r'^ryadom-[0-9a-f]{32}$').hasMatch(invite)) id.text = invite;
    unawaited(loadSaved());
    unawaited(run(loadNetwork));
  }

  Future<void> loadNetwork() async {
    final servers = await engine.turnServers();
    if (mounted)
      setState(() => localRelay =
          servers == null ? engine.relayAllowed : servers.isNotEmpty);
  }

  Future<void> turnSettings() async {
    final saved = await engine.turnServers();
    final first = saved?.isNotEmpty == true ? saved!.first as Map : const {};
    final urls =
        TextEditingController(text: (first['urls'] as List? ?? []).join('\n'));
    final username = TextEditingController(text: first['username'] ?? '');
    final credential = TextEditingController(text: first['credential'] ?? '');
    try {
      if (!mounted) return;
      final servers = await showDialog<List<Map<String, dynamic>>>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Резервный TURN в этом браузере'),
                  content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text(
                            'Параметры сохраняются только в этом браузере. Нужны данные подключения TURN, а не API-ключ аккаунта. Изменения применяются к новым сеансам.'),
                        const SizedBox(height: 16),
                        TextField(
                            controller: urls,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                labelText: 'Адреса TURN, по одному в строке',
                                hintText: 'turn:server.example.com:3478')),
                        TextField(
                            controller: username,
                            decoration: const InputDecoration(
                                labelText: 'Имя пользователя TURN')),
                        TextField(
                            controller: credential,
                            obscureText: true,
                            decoration:
                                const InputDecoration(labelText: 'Пароль TURN'))
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена')),
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(context, <Map<String, dynamic>>[]),
                        child: const Text('Только P2P')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, <Map<String, dynamic>>[
                              {
                                'urls': urls.text
                                    .split(RegExp(r'\s+'))
                                    .where((value) => value.isNotEmpty)
                                    .toList(),
                                'username': username.text.trim(),
                                'credential': credential.text
                              }
                            ]),
                        child: const Text('Сохранить локально'))
                  ]));
      if (servers != null) {
        await engine.saveTurnServers(jsonEncode(servers));
        await loadNetwork();
      }
    } finally {
      urls.dispose();
      username.dispose();
      credential.dispose();
    }
  }

  Future<void> loadSaved() async {
    try {
      final rows = await engine.computers();
      if (mounted) setState(() => saved = rows);
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Браузер запретил локальное хранилище. Разрешите данные сайта.');
    }
  }

  Future<void> run(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  void onEvent(String name, dynamic value) {
    if (!mounted) return;
    if (name == 'connected' && passwordDialogOpen)
      Navigator.pop(context, 'connected');
    if (name == 'password') {
      setState(() {
        status = value.toString();
        busy = false;
      });
      unawaited(passwordDialog(value.toString()));
      return;
    }
    if (name == 'overwrite') {
      unawaited(overwrite(value as Map));
      return;
    }
    setState(() {
      switch (name) {
        case 'status':
          status = value.toString();
          break;
        case 'error':
        case 'warning':
          error = value.toString();
          break;
        case 'connected':
          recovering = false;
          controls = holder == you && you != 0;
          active = true;
          busy = false;
          displays = value['displays'] ?? [];
          monitor = value['currentDisplay'] ?? 0;
          status = 'Зашифрованное соединение';
          unawaited(loadSaved());
          break;
        case 'recovering':
          recovering = true;
          controls = false;
          status = 'Восстанавливаем связь… ${value['remaining']} с';
          break;
        case 'p2p':
          p2pAvailable = value['available'] == true;
          p2pChecking = value['checking'] == true;
          break;
        case 'transport':
          transport = value['relayed'] == null
              ? 'Тип канала уточняется'
              : value['relayed'] == true
                  ? 'TURN — через ретранслятор'
                  : 'P2P ${value['family'] ?? ''} — напрямую';
          break;
        case 'codecTest':
          codecStatus = value['status'] ?? '';
          codecResults = value['results'] ?? [];
          break;
        case 'control':
          you = value['you'] ?? 0;
          holder = value['holder'] ?? 0;
          participants = value['participants'] ?? [];
          controls = !recovering && holder == you && you != 0;
          status = (value['reason'] ?? '').isNotEmpty
              ? value['reason']
              : (controls ? 'Вы управляете' : 'Режим наблюдения');
          break;
        case 'chat':
          messages.add('Собеседник: $value');
          break;
        case 'clipboard':
          clipboard = value.toString();
          break;
        case 'directory':
          files = value['entries'] ?? [];
          path.text = value['path'] ?? path.text;
          break;
        case 'terminalText':
          terminalText += value.toString();
          if (terminalText.length > 200000)
            terminalText = terminalText.substring(terminalText.length - 200000);
          break;
        case 'progress':
          status = 'Передача: ${value['sent']} / ${value['size']} байт';
          break;
        case 'fileDone':
          status = 'Передача завершена';
          break;
        case 'closed':
          active = false;
          busy = false;
          controls = false;
          recording = false;
          status = value.toString();
          break;
      }
    });
  }

  Future<void> connect([String? savedIdentity]) async {
    final peer =
        (savedIdentity ?? id.text).trim().toLowerCase().replaceAll(' ', '');
    if (!RegExp(r'^(ryadom-[0-9a-f]{32}|[1-9][0-9]{8})$').hasMatch(peer)) {
      setState(() => error = 'Введите 9 цифр ID из приложения на удалённом ПК');
      return;
    }
    setState(() {
      busy = true;
      error = '';
      transport = '';
      status = 'Подключаемся…';
    });
    await run(() async {
      await engine.create(peer, onEvent);
      return await engine.call('connect', [password.text, remember]);
    });
    if (mounted && !active) setState(() => busy = false);
  }

  Future<void> passwordDialog(String reason) async {
    if (passwordDialogOpen) return;
    passwordDialogOpen = true;
    final value = TextEditingController();
    bool save = false;
    final accepted = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: const Text('Доступ к компьютеру'),
                    content: SizedBox(
                        width: 380,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(reason),
                          const SizedBox(height: 16),
                          TextField(
                              controller: value,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: 'Пароль удалённого ПК')),
                          CheckboxListTile(
                              value: save,
                              onChanged: (v) => update(() => save = v ?? false),
                              title: const Text('Запомнить на этом устройстве'),
                              contentPadding: EdgeInsets.zero)
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, 'close'),
                          child: const Text('Отмена')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, 'wait'),
                          child: const Text('Дождаться разрешения')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, 'login'),
                          child: const Text('Подключиться'))
                    ])));
    passwordDialogOpen = false;
    if (accepted == 'login') {
      setState(() => busy = true);
      await run(() => engine.call('login', [value.text, save]));
    } else if (accepted == 'close' || accepted == null)
      await run(() => engine.call('close'));
    else if (accepted == 'wait')
      setState(() {
        busy = true;
        status = 'Ожидание разрешения на удалённом ПК';
      });
    value.dispose();
  }

  Future<void> overwrite(Map value) async {
    final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Файл уже существует'),
                content: const Text(
                    'Выберите действие. Существующий файл будет заменён только после вашего подтверждения.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, 'skip'),
                      child: const Text('Пропустить')),
                  if (value['isResume'] == true)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'resume'),
                        child: const Text('Продолжить')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, 'replace'),
                      child: const Text('Заменить'))
                ]));
    await run(() => engine.call('confirmUpload',
        [value['id'], action ?? 'skip', value['transferredSize'] ?? 0]));
  }

  Widget panel(Widget child) =>
      Card(child: Padding(padding: const EdgeInsets.all(28), child: child));
  Widget title(String text) => Text(text,
      style: const TextStyle(
          fontSize: 24, fontWeight: FontWeight.w700, color: ink));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          backgroundColor: Colors.white,
          title: Row(children: [
            Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: blue, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.devices_rounded, color: Colors.white)),
            const SizedBox(width: 12),
            const Text('Рядом', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 16),
            const Text('Удалённая помощь',
                style: TextStyle(fontSize: 15, color: const Color(0xff46556b)))
          ]),
          actions: [
            TextButton.icon(
                onPressed: () => run(turnSettings),
                icon: const Icon(Icons.settings_ethernet),
                label: const Text('TURN')),
            TextButton.icon(
                onPressed: () => showAboutDialog(
                        context: context,
                        applicationName: 'Рядом',
                        applicationVersion: '0.1 • разработка',
                        children: [
                          const Text(
                              'Основано на RustDesk 1.5.3. AGPL-3.0. Этот выпуск ещё проходит разработку и испытания.'),
                          TextButton.icon(
                              onPressed: () => html.window.open(
                                  'source/Ryadom-Sources-development.zip',
                                  '_blank'),
                              icon: const Icon(Icons.code),
                              label:
                                  const Text('Скачать исходники этой сборки')),
                          TextButton(
                              onPressed: () => html.window
                                  .open('THIRD_PARTY_NOTICES.txt', '_blank'),
                              child: const Text('Лицензии компонентов'))
                        ]),
                icon: const Icon(Icons.info_outline),
                label: const Text('О приложении')),
            const SizedBox(width: 20)
          ]),
      body: Column(children: [
        if (error.isNotEmpty)
          MaterialBanner(content: Text(error), actions: [
            TextButton(
                onPressed: () => setState(() => error = ''),
                child: const Text('Понятно'))
          ]),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
            child: Row(children: [
              Icon(active ? Icons.lock_outline : Icons.circle_outlined,
                  size: 16,
                  color: active ? Colors.green : const Color(0xff46556b)),
              const SizedBox(width: 8),
              Expanded(child: Text(status)),
              if (active && transport.isNotEmpty)
                Tooltip(
                    message: transport.startsWith('TURN')
                        ? 'Расходуется квота ретранслятора'
                        : transport.startsWith('P2P')
                            ? 'Квота TURN не расходуется'
                            : 'Ожидаем подтверждения выбранного канала',
                    child: Chip(label: Text(transport))),
              if (busy)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
            ])),
        Expanded(child: active ? sessionView() : home()),
      ]));
  Widget home() => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Быть рядом — просто',
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: ink)),
                    const SizedBox(height: 8),
                    const Text(
                        'Подключитесь к знакомому компьютеру или помогите близким.',
                        style: TextStyle(
                            fontSize: 17, color: const Color(0xff46556b))),
                    const SizedBox(height: 28),
                    LayoutBuilder(builder: (context, box) {
                      final cards = [
                        panel(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.screen_share_outlined,
                                  color: blue, size: 32),
                              const SizedBox(height: 16),
                              title('Дать доступ'),
                              const SizedBox(height: 12),
                              const Text(
                                  'Откройте «Рядом» на удалённом Windows-ПК и передайте его ID. На нём можно нажать «Разрешить» или установить постоянный пароль.'),
                              const SizedBox(height: 20),
                              const Chip(
                                  label: Text('Требуется Windows-приложение')),
                              const SizedBox(height: 8),
                              const Text(
                                  'В браузере доступно управление другим ПК.',
                                  style:
                                      TextStyle(color: const Color(0xff46556b)))
                            ])),
                        panel(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.near_me_outlined,
                                  color: blue, size: 32),
                              const SizedBox(height: 16),
                              title('Подключиться'),
                              const SizedBox(height: 20),
                              TextField(
                                  controller: id,
                                  enabled: !busy,
                                  decoration: const InputDecoration(
                                      labelText: 'ID компьютера',
                                      hintText: 'ryadom-…'),
                                  onSubmitted: (_) => connect()),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: password,
                                  enabled: !busy,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Пароль, если он установлен')),
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: remember,
                                  onChanged: (v) =>
                                      setState(() => remember = v ?? false),
                                  title: const Text(
                                      'Запомнить пароль на этом устройстве')),
                              SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                      onPressed: busy ? null : connect,
                                      icon: const Icon(Icons.arrow_forward),
                                      label: const Padding(
                                          padding: EdgeInsets.all(13),
                                          child: Text('Подключиться')))),
                              if (busy)
                                TextButton(
                                    onPressed: () =>
                                        run(() => engine.call('close')),
                                    child: const Text('Отменить подключение'))
                            ]))
                      ];
                      return box.maxWidth > 760
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Expanded(child: cards[0]),
                                  const SizedBox(width: 18),
                                  Expanded(child: cards[1])
                                ])
                          : Column(children: cards);
                    }),
                    const SizedBox(height: 28),
                    title('История · ${saved.length}'),
                    const SizedBox(height: 16),
                    if (saved.isEmpty)
                      const Text(
                          'После первого подключения компьютер появится здесь.',
                          style: TextStyle(color: const Color(0xff46556b))),
                    if (saved.isNotEmpty)
                      LayoutBuilder(builder: (context, box) {
                        final scale = MediaQuery.textScalerOf(context).scale(1);
                        final columns = (box.maxWidth / (260 * scale))
                            .floor()
                            .clamp(1, 4)
                            .toInt();
                        return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: saved.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisExtent: 38 * scale + 22,
                                    crossAxisSpacing: 6,
                                    mainAxisSpacing: 6),
                            itemBuilder: (_, index) {
                              final peer = saved[index];
                              final code = peer['code']?.toString() ?? '';
                              final number = RegExp(r'^[1-9][0-9]{8}$')
                                      .hasMatch(code)
                                  ? '${code.substring(0, 3)} ${code.substring(3, 6)} ${code.substring(6)}'
                                  : 'ID ещё не сохранён';
                              return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: busy
                                          ? null
                                          : () {
                                              id.text =
                                                  RegExp(r'^[1-9][0-9]{8}$')
                                                          .hasMatch(code)
                                                      ? code
                                                      : '';
                                              connect(peer['id']);
                                            },
                                      child: Padding(
                                          padding: const EdgeInsets.only(
                                              left: 12, right: 4),
                                          child: Row(children: [
                                            const Icon(Icons.computer_outlined,
                                                color: blue, size: 19),
                                            const SizedBox(width: 9),
                                            Expanded(
                                                child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(number,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontFamily:
                                                              'Segoe UI',
                                                          fontSize: 17,
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                  Text(
                                                      peer['name'] ??
                                                          'Сохранённый компьютер',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontSize: 13,
                                                          color: const Color(
                                                              0xff46556b))),
                                                ])),
                                            IconButton(
                                                tooltip:
                                                    'Забыть компьютер и пароль',
                                                icon: const Icon(Icons.close,
                                                    size: 16),
                                                onPressed: () => run(() async {
                                                      await engine
                                                          .forget(peer['id']);
                                                      await loadSaved();
                                                    })),
                                          ]))));
                            });
                      }),
                    const SizedBox(height: 30),
                    Text(
                        localRelay
                            ? 'Разработка · Прямое соединение, резервный TURN с ограниченной квотой.'
                            : 'Разработка · Личный TURN не настроен; можно использовать резерв удалённого ПК.',
                        style: const TextStyle(color: const Color(0xff46556b))),
                  ]))));
  Future<void> codecDetails() async {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Проверка кодеков'),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(codecStatus),
                      const SizedBox(height: 12),
                      const Text(
                          'Прокрутите документ или перемещайте окно. Сравниваются FPS, задержка и трафик при выбранном качестве изображения. Эталонное сравнение пикселей не выполняется.'),
                      if (codecResults.isNotEmpty)
                        DataTable(
                            columns: const [
                              DataColumn(label: Text('Кодек')),
                              DataColumn(label: Text('FPS')),
                              DataColumn(label: Text('мс')),
                              DataColumn(label: Text('КБ/с'))
                            ],
                            rows: codecResults
                                .map((r) => DataRow(cells: [
                                      DataCell(
                                          Text('${r['codec']}'.toUpperCase())),
                                      DataCell(Text((r['fps'] as num)
                                          .toStringAsFixed(1))),
                                      DataCell(Text((r['delayMs'] as num)
                                          .toStringAsFixed(0))),
                                      DataCell(Text(
                                          ((r['bytesPerSecond'] as num) / 1024)
                                              .toStringAsFixed(0)))
                                    ]))
                                .toList())
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Закрыть'))
                ]));
  }

  Widget sessionView() => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (recovering) Text(status),
          if (transport.isNotEmpty) Chip(label: Text(transport)),
          if (p2pAvailable)
            TextButton(
                onPressed: () => run(() => engine.call('switchToP2P')),
                child: const Text('Перейти на P2P')),
          if (!p2pAvailable && transport.startsWith('TURN'))
            IconButton(
                tooltip: 'Проверить P2P',
                onPressed: p2pChecking
                    ? null
                    : () => run(() => engine.call('checkP2P')),
                icon: const Icon(Icons.router_outlined)),
          IconButton(
              tooltip:
                  sessionToolbarVisible ? 'Скрыть панель' : 'Показать панель',
              onPressed: () => setState(
                  () => sessionToolbarVisible = !sessionToolbarVisible),
              icon: Icon(sessionToolbarVisible
                  ? Icons.expand_less
                  : Icons.expand_more)),
        ]),
        if (sessionToolbarVisible)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                        avatar: Icon(
                            controls
                                ? Icons.mouse_outlined
                                : Icons.visibility_outlined,
                            size: 18),
                        label:
                            Text(controls ? 'Вы управляете' : 'Вы наблюдаете')),
                    PopupMenuButton<String>(
                        tooltip: codecStatus,
                        onSelected: (value) => value == 'results'
                            ? codecDetails()
                            : run(() => engine.call('setCodec', [value])),
                        itemBuilder: (_) => [
                              if (controls)
                                const PopupMenuItem(
                                    value: 'auto',
                                    child: Text('Авто — проверить кодеки')),
                              if (controls)
                                const PopupMenuItem(
                                    value: 'vp8', child: Text('VP8 — вручную')),
                              if (controls)
                                const PopupMenuItem(
                                    value: 'vp9', child: Text('VP9 — вручную')),
                              if (controls)
                                const PopupMenuItem(
                                    value: 'av1', child: Text('AV1 — вручную')),
                              const PopupMenuItem(
                                  value: 'results',
                                  child: Text('Результаты проверки'))
                            ],
                        icon: const Icon(Icons.speed_outlined)),
                    DropdownButton<int>(
                        value: monitor,
                        items: [
                          for (var i = 0; i < displays.length; i++)
                            DropdownMenuItem(
                                value: i, child: Text('Монитор ${i + 1}'))
                        ],
                        onChanged: (v) => run(() async {
                              monitor = v ?? 0;
                              await engine.call('monitor', [monitor]);
                              setState(() {});
                            })),
                    if (!controls)
                      OutlinedButton(
                          onPressed: () =>
                              run(() => engine.call('control', ['claim'])),
                          child: const Text('Получить управление')),
                    if (controls)
                      PopupMenuButton<int>(
                          tooltip: 'Передать управление',
                          onSelected: (v) => run(
                              () => engine.call('control', ['transfer', v])),
                          itemBuilder: (_) => [
                                for (final p in participants)
                                  if (p['id'] != you)
                                    PopupMenuItem(
                                        value: p['id'],
                                        child: Text(p['name'] ?? 'Участник'))
                              ],
                          child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Text('Передать управление'))),
                    OutlinedButton.icon(
                        onPressed: () => run(() => engine.media('enableAudio')),
                        icon: const Icon(Icons.volume_up_outlined),
                        label: const Text('Включить звук')),
                    OutlinedButton.icon(
                        onPressed: () => run(() async {
                              await engine.media(recording
                                  ? 'stopRecording'
                                  : 'startRecording');
                              setState(() => recording = !recording);
                            }),
                        icon: Icon(recording
                            ? Icons.stop_circle_outlined
                            : Icons.fiber_manual_record_outlined),
                        label:
                            Text(recording ? 'Остановить запись' : 'Запись')),
                    TextButton.icon(
                        onPressed: () => run(() => engine.call('close')),
                        icon: const Icon(Icons.call_end, color: Colors.red),
                        label: const Text('Завершить')),
                  ])),
        Expanded(
            child: Row(children: [
          Expanded(
              flex: 3,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child:
                          const HtmlElementView(viewType: 'ryadom-screen')))),
          SizedBox(
              width: 340,
              child: Column(children: [
                SegmentedButton<int>(segments: const [
                  ButtonSegment(value: 0, label: Text('Чат')),
                  ButtonSegment(value: 1, label: Text('Файлы')),
                  ButtonSegment(value: 2, label: Text('Ещё'))
                ], selected: {
                  tab
                }, onSelectionChanged: (v) => setState(() => tab = v.first)),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: tab == 0
                            ? chatView()
                            : tab == 1
                                ? fileView()
                                : moreView())),
              ]))
        ])),
      ]);
  Widget chatView() => Column(children: [
        Expanded(
            child: ListView(
                children: messages
                    .map((m) => Padding(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(m)))
                    .toList())),
        TextField(
            controller: chat,
            decoration: const InputDecoration(labelText: 'Сообщение'),
            onSubmitted: (value) => sendChat()),
        const SizedBox(height: 8),
        FilledButton(onPressed: sendChat, child: const Text('Отправить'))
      ]);
  void sendChat() => run(() async {
        if (chat.text.trim().isEmpty) return;
        await engine.call('chat', [chat.text]);
        setState(() => messages.add('Вы: ${chat.text}'));
        chat.clear();
      });
  Widget fileView() => Column(children: [
        TextField(
            controller: path,
            decoration:
                const InputDecoration(labelText: 'Папка на удалённом ПК'),
            enabled: controls,
            onSubmitted: (_) =>
                run(() => engine.call('directory', [path.text]))),
        const SizedBox(height: 8),
        Wrap(children: [
          IconButton(
              tooltip: 'На уровень выше',
              onPressed: controls
                  ? () => run(() {
                        final parts = path.text
                            .replaceAll('/', '\\')
                            .replaceAll(RegExp(r'\\+$'), '');
                        final at = parts.lastIndexOf('\\');
                        final parent = at < 0 ? '' : parts.substring(0, at + 1);
                        return engine.call('directory', [parent]);
                      })
                  : null,
              icon: const Icon(Icons.arrow_upward)),
          TextButton(
              onPressed: controls
                  ? () => run(() => engine.call('directory', [path.text]))
                  : null,
              child: const Text('Открыть')),
          TextButton(
              onPressed: controls ? upload : null,
              child: const Text('Загрузить файлы')),
          TextButton(
              onPressed: controls ? () => changeFile('create') : null,
              child: const Text('Новая папка'))
        ]),
        if (controls)
          const SizedBox(
              height: 68, child: HtmlElementView(viewType: 'ryadom-file-drop')),
        const SizedBox(height: 8),
        Expanded(
            child: ListView(
                children: files
                    .map((f) => ListTile(
                        dense: true,
                        leading: Icon((f['entryType'] ?? 0) < 4
                            ? Icons.folder_outlined
                            : Icons.description_outlined),
                        title: Text(f['name']),
                        subtitle: (f['entryType'] ?? 0) < 4
                            ? null
                            : Text('${f['size'] ?? 0} байт'),
                        trailing: controls
                            ? PopupMenuButton<String>(
                                onSelected: (action) => changeFile(action, f),
                                itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Переименовать')),
                                      PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Удалить'))
                                    ])
                            : null,
                        onTap: !controls
                            ? null
                            : () => run(() {
                                  final full = filePath(f['name']);
                                  return (f['entryType'] ?? 0) < 4
                                      ? engine.call('directory', [full])
                                      : engine.call('download', [
                                          full,
                                          f['name'],
                                          int.parse('${f['size'] ?? 0}')
                                        ]);
                                })))
                    .toList()))
      ]);
  void upload() {
    final input = html.FileUploadInputElement()..multiple = true;
    input.click();
    input.onChange.first.then((_) {
      if (input.files?.isNotEmpty ?? false)
        unawaited(uploadFiles(input.files!));
    });
  }

  String filePath(String name) {
    if (path.text.isEmpty || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(name))
      return name;
    return '${path.text}${path.text.endsWith('\\') ? '' : '\\'}$name';
  }

  Future<void> uploadFiles(List<html.File> items) => run(() async {
        for (final file in items) {
          await engine.call('upload', [file, path.text]);
        }
        await engine.call('directory', [path.text]);
      });

  Future<void> changeFile(String action, [dynamic entry]) async {
    if (!controls) return;
    if (action == 'remove') {
      final folder = (entry['entryType'] ?? 0) < 4;
      final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text('Удалить ${entry['name']}?'),
                  content: Text(folder
                      ? 'Папка и всё её содержимое будут удалены с удалённого ПК без корзины.'
                      : 'Файл будет удалён с удалённого ПК без корзины.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Отмена')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Удалить'))
                  ]));
      if (yes != true) return;
      await run(() async {
        await engine.call('remove', [filePath(entry['name']), folder]);
        await engine.call('directory', [path.text]);
      });
      return;
    }
    final name =
        TextEditingController(text: action == 'rename' ? entry['name'] : '');
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title:
                    Text(action == 'rename' ? 'Переименовать' : 'Новая папка'),
                content: TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Имя'),
                    onSubmitted: (_) => Navigator.pop(context, name.text)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, name.text),
                      child: const Text('Сохранить'))
                ]));
    name.dispose();
    if (value == null) return;
    await run(() async {
      if (value.trim().isEmpty ||
          value == '.' ||
          value == '..' ||
          RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(value))
        throw Exception(
            'Укажите допустимое имя Windows без разделителей пути.');
      await engine.call(
          action == 'rename' ? 'rename' : 'createDirectory',
          action == 'rename'
              ? [filePath(entry['name']), value]
              : [filePath(value)]);
      await engine.call('directory', [path.text]);
    });
  }

  Widget moreView() => SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: allowClipboard,
            onChanged: (v) {
              setState(() => allowClipboard = v ?? false);
              engine.clipboard(allowClipboard);
            },
            title: const Text('Текстовый буфер обмена')),
        if (allowClipboard) ...[
          TextButton(
              onPressed: controls
                  ? () => run(() async {
                        final value = await Clipboard.getData('text/plain');
                        await engine.call('paste', [value?.text ?? '']);
                      })
                  : null,
              child: const Text('Вставить мой буфер на удалённом ПК')),
          if (clipboard.isNotEmpty)
            TextButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: clipboard)),
                child: const Text('Скопировать удалённый буфер'))
        ],
        const Divider(),
        OutlinedButton(
            onPressed: controls
                ? () => run(() async {
                      setState(() => terminalVisible = true);
                      await engine.call('terminalOpen');
                    })
                : null,
            child: const Text('Открыть терминал Windows')),
        if (terminalVisible)
          const SizedBox(
              height: 350, child: HtmlElementView(viewType: 'ryadom-terminal')),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: controls
                ? () => run(() async {
                      final yes = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                                  title:
                                      const Text('Перезагрузить удалённый ПК?'),
                                  content: const Text(
                                      'Несохранённые документы могут быть потеряны. Для повторного входа нужен установленный режим и разрешённый постоянный доступ.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Отмена')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Перезагрузить'))
                                  ]));
                      if (yes == true) await engine.call('reboot');
                    })
                : null,
            child: const Text('Перезагрузить компьютер')),
      ]));
  @override
  void dispose() {
    id.dispose();
    password.dispose();
    chat.dispose();
    path.dispose();
    terminal.dispose();
    super.dispose();
  }
}
