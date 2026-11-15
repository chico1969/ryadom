import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:get/get.dart';

class RyadomTransportBadge extends StatelessWidget {
  const RyadomTransportBadge({super.key, required this.peerId});
  final String peerId;

  @override
  Widget build(BuildContext context) => Obx(() {
        final state = ConnectionTypeState.find(peerId);
        if (!state.isValid()) return const SizedBox.shrink();
        final relay = state.direct.value == ConnectionType.strIndirect;
        final color = relay ? Colors.orange.shade800 : Colors.green.shade700;
        return Tooltip(
            message: relay
                ? 'Сеанс передаётся через TURN. Расходуется квота ретранслятора.'
                : 'Сеанс идёт напрямую между компьютерами. Квота TURN не расходуется.',
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(relay ? Icons.cloud_outlined : Icons.swap_horiz,
                      color: color, size: 18),
                  const SizedBox(width: 5),
                  Text(
                      relay
                          ? 'TURN'
                          : (state.stream_type.value.contains('IPv6')
                              ? 'P2P IPv6'
                              : 'P2P IPv4'),
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w700))
                ])));
      });
}
