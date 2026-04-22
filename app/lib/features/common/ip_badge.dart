import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Плашка в AppBar: показывает текущий публичный IP,
/// с кнопкой глаз/перечёркнутый-глаз для маскировки.
class IpBadge extends ConsumerStatefulWidget {
  const IpBadge({super.key});

  @override
  ConsumerState<IpBadge> createState() => _IpBadgeState();
}

class _IpBadgeState extends ConsumerState<IpBadge> {
  String? _ip;
  bool _hidden = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final preset = ref.read(currentClientPresetProvider);
      final ip = await ref.read(networkServiceProvider).publicIp(preset: preset);
      if (!mounted) return;
      setState(() => _ip = ip);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final show = (ref.watch(showIpProvider) ?? 'true') == 'true';
    if (!show) return const SizedBox.shrink();

    final text = _loading
        ? '…'
        : (_ip == null ? '—' : (_hidden ? _mask(_ip!) : _ip!));

    return Tooltip(
      message: _hidden ? 'IP скрыт' : 'Публичный IP (через текущий preset)',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _refresh,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(text, style: const TextStyle(fontSize: 12)),
              ),
            ),
            IconButton(
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _hidden = !_hidden),
            ),
          ],
        ),
      ),
    );
  }

  String _mask(String ip) {
    // 203.0.113.42 → 203.***.***.42
    final parts = ip.split('.');
    if (parts.length == 4) return '${parts[0]}.***.***.${parts[3]}';
    if (ip.length <= 6) return '***';
    return '${ip.substring(0, 2)}***${ip.substring(ip.length - 2)}';
  }
}
