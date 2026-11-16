import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:window_manager/window_manager.dart';
import 'home_content.dart';
import 'p2p_panel.dart';
import 'native_network_stub.dart' if (dart.library.io) 'native_network.dart';

class RyadomHomePage extends StatefulWidget {
  const RyadomHomePage(
      {super.key, required this.onSetPassword, this.onSettings});
  final VoidCallback onSetPassword;
  final VoidCallback? onSettings;
  @override
  State<RyadomHomePage> createState() => _RyadomHomeState();
}

class _RyadomHomeState extends State<RyadomHomePage> with WindowListener {
  final peer = TextEditingController();
  String error = '';
  bool relayConfigured = false;
  Map<String, dynamic> registration = {};
  Timer? registrationTimer;
  bool registrationPending = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(refreshRegistration());
    registrationTimer = Timer.periodic(
        const Duration(seconds: 2), (_) => refreshRegistration());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) bind.mainLoadRecentPeers();
    });
    try {
      relayConfigured = ownerTurnConfigured();
    } catch (e) {
      error = e.toString();
    }
  }

  Future<void> refreshRegistration() async {
    if (registrationPending) return;
    registrationPending = true;
    try {
      final next = await ryadomRegistrationState();
      if (mounted) setState(() => registration = next);
    } catch (error) {
      if (mounted) {
        setState(() => registration = {
              'phase': 'failed',
              'message':
                  'Не удалось прочитать состояние приёма подключений. Перезапустите Рядом.'
            });
      }
    } finally {
      registrationPending = false;
    }
  }

  String get localId => registration.isEmpty
      ? gFFI.serverModel.serverId.text.replaceAll(RegExp(r'\s'), '')
      : (registration['code'] as String? ?? '');
  @override
  void onWindowFocus() => bind.mainLoadRecentPeers();
  @override
  void onWindowRestore() => bind.mainLoadRecentPeers();
  String historyCode(String id) {
    final code = bind.mainGetPeerOptionSync(id: id, key: 'ryadom-last-code');
    return code.isNotEmpty
        ? code
        : bind.getLocalFlutterOption(k: 'ryadom-code-$id');
  }

  Future<void> open([String? saved]) async {
    final id =
        (saved ?? peer.text).trim().toLowerCase().replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^(ryadom-[0-9a-f]{32}|[1-9][0-9]{8})$').hasMatch(id)) {
      setState(() => error = 'Введите 9 цифр ID компьютера');
      return;
    }
    setState(() => error = '');
    try {
      final resolved = await resolveRyadomPeer(id);
      if (RegExp(r'^[1-9][0-9]{8}$').hasMatch(id)) {
        await bind.setLocalFlutterOption(k: 'ryadom-code-$resolved', v: id);
      }
      if (mounted) await connect(context, resolved);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([gFFI.serverModel, gFFI.recentPeersModel]),
      builder: (context, _) => RyadomHomeContent(
          localId: localId,
          target: peer,
          error: error,
          registrationMessage: registration['message'] as String? ?? '',
          registrationFailed:
              ['failed', 'stopped'].contains(registration['phase']),
          relayConfigured: relayConfigured,
          onSettings: widget.onSettings,
          onNetwork: () async {
            await showRyadomP2P(context);
            if (mounted) {
              setState(() => relayConfigured = ownerTurnConfigured());
            }
          },
          onHelpP2P: () => showRyadomP2P(context, enable: true),
          onStartReceiving: registration['phase'] == 'stopped' && !bind.isOutgoingOnly()
              ? () async {
                  try {
                    await start_service(true);
                    await refreshRegistration();
                  } catch (e) {
                    if (mounted) setState(() => error = e.toString());
                  }
                }
              : null,
          computers: gFFI.recentPeersModel.peers
              .map((saved) => RyadomComputer(
                  id: saved.id,
                  code: historyCode(saved.id),
                  name: saved.alias.isNotEmpty ? saved.alias : saved.hostname))
              .toList(),
          onConnect: () => open(),
          onOpenComputer: (id) => open(id),
          onCopy: () => Clipboard.setData(ClipboardData(text: localId)),
          onSetPassword: widget.onSetPassword));
  @override
  void dispose() {
    windowManager.removeListener(this);
    registrationTimer?.cancel();
    peer.dispose();
    super.dispose();
  }
}
