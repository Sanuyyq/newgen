import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/engines/session_manager.dart';
import '../../core/models/engine_kind.dart';
import '../../core/models/profile.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers.dart';

/// Переиспользуемый контент вкладки (VLESS или AWG): выбор профиля,
/// Connect-кнопка, индикатор статуса, счётчики трафика.
class EngineTab extends ConsumerWidget {
  const EngineTab({super.key, required this.engine});

  final EngineKind engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(profilesProvider(engine));
    final selectedId = ref.watch(selectedProfileProvider(engine));
    final statusAsync = ref.watch(vpnStatusProvider);

    return SafeArea(
      child: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (profiles) {
          final selected = _findSelected(profiles, selectedId);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileCard(
                engine: engine,
                profiles: profiles,
                selected: selected,
                onSelect: (id) =>
                    ref.read(selectedProfileProvider(engine).notifier).select(id),
              ),
              const SizedBox(height: 16),
              _StatusCard(engine: engine, statusAsync: statusAsync),
              const SizedBox(height: 24),
              _ConnectButton(
                engine: engine,
                profile: selected,
                status: statusAsync.asData?.value ?? const VpnStatus(),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.push('/profiles/${_routeKind(engine)}'),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Управлять профилями'),
              ),
            ],
          );
        },
      ),
    );
  }

  VpnProfile? _findSelected(List<VpnProfile> profiles, int? id) {
    if (profiles.isEmpty) return null;
    if (id != null) {
      for (final p in profiles) {
        if (p.id == id) return p;
      }
    }
    return profiles.first;
  }

  static String _routeKind(EngineKind e) => e == EngineKind.vless ? 'vless' : 'awg';
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.engine,
    required this.profiles,
    required this.selected,
    required this.onSelect,
  });

  final EngineKind engine;
  final List<VpnProfile> profiles;
  final VpnProfile? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Профиль ${engine.label}',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            if (profiles.isEmpty)
              const Text('Нет профилей. Добавьте подписку или конфиг.')
            else
              DropdownButton<int>(
                isExpanded: true,
                value: selected?.id,
                items: [
                  for (final p in profiles)
                    DropdownMenuItem(
                      value: p.id,
                      child: Tooltip(
                        message: '${p.name}'
                            '${p.remark != null ? "\n${p.remark}" : ""}'
                            '${p.latencyMs != null ? "\n${p.latencyMs} ms" : ""}',
                        child: Text(
                          '${p.name}${p.isBuiltin ? "  · builtin" : ""}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
                onChanged: onSelect,
              ),
            if (selected != null) ...[
              const SizedBox(height: 8),
              Text(_profileSummary(selected!),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  String _profileSummary(VpnProfile p) {
    if (p.engine == EngineKind.vless) {
      return '${p.config['address']}:${p.config['port']}  · '
          '${p.config['security']} / ${p.config['type']}';
    }
    final peer = p.config['peer'] as Map?;
    return 'endpoint: ${peer?['endpoint'] ?? "?"}';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.engine, required this.statusAsync});

  final EngineKind engine;
  final AsyncValue<VpnStatus> statusAsync;

  @override
  Widget build(BuildContext context) {
    final status = statusAsync.asData?.value ?? const VpnStatus();
    final isOurs = status.engine == engine;
    final state = isOurs ? status.state : VpnState.disconnected;
    final color = switch (state) {
      VpnState.connected => Colors.greenAccent,
      VpnState.connecting || VpnState.disconnecting => Colors.amberAccent,
      VpnState.error => Colors.redAccent,
      VpnState.disconnected => Colors.white54,
    };
    final label = switch (state) {
      VpnState.connected => 'Подключено',
      VpnState.connecting => 'Подключение…',
      VpnState.disconnecting => 'Отключение…',
      VpnState.error => 'Ошибка',
      VpnState.disconnected => 'Отключено',
    };

    final otherActive = status.isActive && !isOurs;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  if (isOurs && state == VpnState.connected)
                    Text(
                      '↑ ${_fmt(status.uploadBytes)}   ↓ ${_fmt(status.downloadBytes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (otherActive)
                    Text(
                      'Активен ${status.engine?.label}. При подключении здесь он будет остановлен.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (status.errorMessage != null)
                    Text(status.errorMessage!,
                        style: const TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

class _ConnectButton extends ConsumerStatefulWidget {
  const _ConnectButton({
    required this.engine,
    required this.profile,
    required this.status,
  });

  final EngineKind engine;
  final VpnProfile? profile;
  final VpnStatus status;

  @override
  ConsumerState<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends ConsumerState<_ConnectButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isOurs = widget.status.engine == widget.engine;
    final connected = isOurs && widget.status.state == VpnState.connected;
    final connecting = isOurs &&
        (widget.status.state == VpnState.connecting ||
            widget.status.state == VpnState.disconnecting);
    final label = connected
        ? 'Отключить'
        : (connecting ? 'Подождите…' : 'Подключить');
    final disabled = _busy || widget.profile == null || connecting;

    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: disabled ? null : _onPressed,
        icon: Icon(connected ? Icons.stop_circle_outlined : Icons.play_arrow),
        label: Text(label),
      ),
    );
  }

  Future<void> _onPressed() async {
    final session = ref.read(vpnSessionProvider);
    final profile = widget.profile;
    if (profile == null) return;

    setState(() => _busy = true);
    try {
      final isOurs = widget.status.engine == widget.engine;
      final connected = isOurs && widget.status.state == VpnState.connected;
      if (connected) {
        await session.disconnect();
      } else {
        // Жёсткий switch: session.connect сам остановит другой движок.
        await session.connect(profile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
