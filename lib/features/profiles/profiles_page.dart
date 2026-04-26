import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/engine_kind.dart';
import '../../core/models/profile.dart';
import '../../core/models/subscription.dart';
import '../../core/parsing/vless_parser.dart';
import '../../core/providers.dart';
import '../../core/services/export_service.dart';
import '../../core/storage/database.dart';

class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key, required this.engine});

  final EngineKind engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(subscriptionsProvider(engine));
    final profilesAsync = ref.watch(profilesProvider(engine));

    return Scaffold(
      appBar: AppBar(title: Text('${engine.label} · профили')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
        onPressed: () =>
            context.push('/profiles/${engine == EngineKind.vless ? "vless" : "awg"}/add'),
      ),
      body: subsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (subs) => profilesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Ошибка: $e')),
          data: (profiles) {
            final grouped = <int?, List<VpnProfile>>{};
            for (final p in profiles) {
              grouped.putIfAbsent(p.subscriptionId, () => []).add(p);
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final s in subs)
                  _SubscriptionTile(
                    engine: engine,
                    sub: s,
                    profiles: grouped[s.id] ?? const [],
                  ),
                if (subs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Пока нет подписок.'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SubscriptionTile extends ConsumerWidget {
  const _SubscriptionTile({
    required this.engine,
    required this.sub,
    required this.profiles,
  });

  final EngineKind engine;
  final Subscription sub;
  final List<VpnProfile> profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = [
      sub.source.name,
      if (sub.url != null) sub.url!,
      '${profiles.length} профилей',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Tooltip(
          message: '${sub.name}\nsource: ${sub.source.name}'
              '${sub.url != null ? "\n${sub.url}" : ""}',
          child: Text(sub.name),
        ),
        subtitle: Text(subtitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Экспорт ключей',
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: () => _showExport(context, profiles),
            ),
            if (sub.source == SubscriptionSource.builtin)
              const Icon(Icons.lock_outline, size: 18)
            else
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref),
              ),
          ],
        ),
        children: [
          for (final p in profiles) _ProfileRow(profile: p),
        ],
      ),
    );
  }

  void _showExport(BuildContext context, List<VpnProfile> ps) {
    final vless = ExportService.toVlessLinks(ps);
    final awg = ExportService.toAwgConfs(ps);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, ctrl) {
          final text = [
            if (vless.isNotEmpty) '# VLESS', ...vless,
            if (awg.isNotEmpty) '\n# AmneziaWG', ...awg,
          ].join('\n');
          return ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text('Экспорт (${vless.length} vless + ${awg.length} awg)',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Скопировать',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Скопировано')));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (vless.length == 1) ...[
                Center(
                  child: QrImageView(
                    data: vless.first,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SelectableText(text,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить "${sub.name}"?'),
        content: const Text('Будут удалены все связанные профили.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseProvider).deleteSubscription(sub.id!);
    bumpRefresh(ref);
  }
}

class _ProfileRow extends ConsumerStatefulWidget {
  const _ProfileRow({required this.profile});

  final VpnProfile profile;

  @override
  ConsumerState<_ProfileRow> createState() => _ProfileRowState();
}

class _ProfileRowState extends ConsumerState<_ProfileRow> {
  bool _testing = false;
  String? _lastSpeed;

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final selectedId = ref.watch(selectedProfileProvider(profile.engine));
    final isSelected = selectedId == profile.id;
    final host = _host(profile);
    final tooltipText = '${profile.name}\n$host'
        '${profile.latencyMs != null ? "\n${profile.latencyMs} ms" : ""}'
        '${_lastSpeed != null ? "\nspeed: $_lastSpeed" : ""}'
        '${profile.remark != null ? "\n${profile.remark}" : ""}';

    return Tooltip(
      message: tooltipText,
      waitDuration: const Duration(milliseconds: 300),
      child: ListTile(
        dense: true,
        leading: Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
          size: 18,
        ),
        title: Text(profile.name, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(host,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            _LatencyChip(ms: profile.latencyMs),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Speedtest',
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt, size: 20),
              onPressed: _testing ? null : _speedTest,
            ),
            IconButton(
              tooltip: 'Показать vless://',
              icon: const Icon(Icons.qr_code, size: 20),
              onPressed: () => _showKey(context, profile),
            ),
            if (!profile.isBuiltin)
              IconButton(
                tooltip: 'Удалить',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  await ref.read(databaseProvider).deleteProfile(profile.id!);
                  bumpRefresh(ref);
                },
              ),
          ],
        ),
        onTap: () => ref
            .read(selectedProfileProvider(profile.engine).notifier)
            .select(profile.id),
      ),
    );
  }

  String _host(VpnProfile p) => p.engine == EngineKind.vless
      ? '${p.config['address']}:${p.config['port']}'
      : '${(p.config['peer'] as Map?)?['endpoint'] ?? ''}';

  Future<void> _speedTest() async {
    setState(() => _testing = true);
    try {
      final net = ref.read(networkServiceProvider);
      final preset = ref.read(currentClientPresetProvider);
      final r = await net.speedTest(preset: preset);
      setState(() =>
          _lastSpeed = '${(r.downloadKbps / 1000).toStringAsFixed(2)} Mbps');
    } catch (e) {
      setState(() => _lastSpeed = 'err');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showKey(BuildContext context, VpnProfile p) {
    if (p.engine != EngineKind.vless) {
      final text = ExportService.toAwgConfs([p]).firstOrNull ?? '';
      _showText(context, text);
      return;
    }
    final link = VlessParser.build(name: p.name, c: p.config);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: link,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 12),
            SelectableText(link, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Скопировать'),
              onPressed: () => Clipboard.setData(ClipboardData(text: link)),
            ),
          ],
        ),
      ),
    );
  }

  void _showText(BuildContext context, String text) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Скопировать'),
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatencyChip extends StatelessWidget {
  const _LatencyChip({required this.ms});
  final int? ms;

  @override
  Widget build(BuildContext context) {
    if (ms == null) return const SizedBox.shrink();
    final color = ms! < 100
        ? Colors.greenAccent
        : (ms! < 300 ? Colors.amberAccent : Colors.redAccent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$ms ms',
          style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

extension on Iterable<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
