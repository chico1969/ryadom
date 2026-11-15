import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

typedef _RequestNative = Int32 Function(
    Pointer<Uint8>, Uint32, Pointer<Uint8>, Uint32);
typedef _Request = int Function(Pointer<Uint8>, int, Pointer<Uint8>, int);

class RyadomControlButton extends StatefulWidget {
  final String session;
  const RyadomControlButton({super.key, required this.session});
  @override
  State<RyadomControlButton> createState() => _ControlState();
}

class _ControlState extends State<RyadomControlButton> {
  Timer? timer;
  _Request? request;
  Map<String, dynamic> state = {};
  @override
  void initState() {
    super.initState();
    try {
      request = DynamicLibrary.open(path.join(
              path.dirname(Platform.resolvedExecutable), 'librustdesk.dll'))
          .lookupFunction<_RequestNative, _Request>('ryadom_request_v1');
      poll();
      timer = Timer.periodic(const Duration(milliseconds: 500), (_) => poll());
    } catch (e) {
      state = {'error': e.toString()};
    }
  }

  Map<String, dynamic> call(String action, [int target = 0]) {
    final input = jsonEncode(
            {'session': widget.session, 'action': action, 'target': target})
        .toNativeUtf8(allocator: calloc);
    final output = calloc<Uint8>(65536);
    try {
      final count = request!(input.cast(),
          utf8.encode(input.toDartString()).length, output, 65536);
      if (count < 0) throw StateError('Ошибка моста управления: $count');
      return jsonDecode(utf8.decode(output.asTypedList(count)))
          as Map<String, dynamic>;
    } finally {
      calloc.free(output);
      calloc.free(input);
    }
  }

  void poll() {
    if (request == null) return;
    try {
      final next = call('local-state');
      if (mounted) setState(() => state = next);
    } catch (e) {
      if (mounted) setState(() => state = {'error': e.toString()});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controls = state['you'] != null && state['you'] == state['holder'];
    return PopupMenuButton<String>(
        enabled: request != null,
        tooltip: controls ? 'Вы управляете' : 'Вы наблюдаете',
        icon: Icon(controls ? Icons.mouse_outlined : Icons.visibility_outlined),
        onSelected: (action) {
          final parts = action.split(':');
          final result =
              call(parts.first, parts.length > 1 ? int.parse(parts[1]) : 0);
          if (result['error'] != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(result['error'])));
          }
        },
        itemBuilder: (_) => [
              PopupMenuItem(
                  enabled: false,
                  child: Text(controls ? 'Вы управляете' : 'Вы наблюдаете')),
              if ((state['reason'] ?? '').isNotEmpty)
                PopupMenuItem(enabled: false, child: Text(state['reason'])),
              if (!controls)
                const PopupMenuItem(
                    value: 'claim', child: Text('Получить управление')),
              if (controls) ...[
                const PopupMenuItem(
                    value: 'release', child: Text('Освободить управление')),
                for (final p in state['participants'] ?? [])
                  if (p['id'] != state['you'])
                    PopupMenuItem(
                        value: 'transfer:${p['id']}',
                        child: Text('Передать: ${p['name']}'))
              ],
            ]);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
