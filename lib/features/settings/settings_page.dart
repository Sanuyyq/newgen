import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/client_preset.dart';
import '../../core/providers.dart';
import '../../core/services/lan_proxy_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _remoteCtrl;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _remoteCtrl = TextEditingController(
      text: ref.read(remoteBuiltinUrlProvider) ?? '',
    );
  }

  @override
  void dispose() {
    _remoteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Подтягиваем актуальное значение после async-загрузки.
    ref.listen<String?>(remoteBuiltinUrlProvider, (_, next) {
      if (next != null && _remoteCtrl.text.isEmpty) _remoteCtrl.text = next;
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Источник встроенных профилей',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Если указан HTTPS-URL, приложение подтянет с него актуальный '
            'список встроенных серверов. Иначе используется локальный '
            'assets/builtin_profiles.json.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remoteCtrl,
            decoration: const InputDecoration(
              labelText: 'remoteBuiltinUrl',
              hintText: 'https://example.com/negern/builtin.txt',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _save,
                child: const Text('Сохранить'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Синхронизировать'),
              ),
            ],
          ),
          const Divider(height: 48),
          _ClientPresetSection(),
          const Divider(height: 48),
          _ConnectionModeSection(),
          const Divider(height: 48),
          _WallpaperSection(),
          const Divider(height: 48),
          _AutotestSection(),
          const Divider(height: 48),
          _ShareProxySection(),
          const Divider(height: 48),
          _IpVisibilitySection(),
          const Divider(height: 48),
          Text('О приложении',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Negern VPN — скелет. Реальные движки (Xray / AWG) подключаются '
            'на следующих итерациях. Раздача интернета работает через '
            'встроенный SOCKS5-сервер: Wi-Fi SoftAP из клиентского '
            'приложения сделать нельзя без системных API ОС, поэтому '
            'LAN-шаринг — единственный способ, не зависящий от встроенных '
            'утилит.',
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final url = _remoteCtrl.text.trim();
    await ref
        .read(remoteBuiltinUrlProvider.notifier)
        .set(url.isEmpty ? null : url);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Сохранено')));
  }

  Future<void> _sync() async {
    final url = _remoteCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _syncing = true);
    try {
      await ref.read(subscriptionServiceProvider).syncRemoteBuiltin(url: url);
      bumpRefresh(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Список обновлён')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
}

class _ClientPresetSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(clientPresetIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Подмена клиента (fingerprint / User-Agent)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Для серверов, принимающих только определённые клиенты (Happ, '
          'NekoBox и т.п.). Влияет на fingerprint в Reality и User-Agent '
          'при скачивании подписок.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in ClientPreset.all)
              ChoiceChip(
                label: Text(p.name),
                selected: (currentId ?? ClientPreset.negern.id) == p.id,
                onSelected: (_) =>
                    ref.read(clientPresetIdProvider.notifier).set(p.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _ConnectionModeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(connectionModeProvider) ?? ConnectionMode.tun.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Режим подключения',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final m in ConnectionMode.values)
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: Text(m.label),
            value: m.name,
            groupValue: mode,
            onChanged: (v) =>
                ref.read(connectionModeProvider.notifier).set(v),
          ),
      ],
    );
  }
}

class _WallpaperSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(wallpaperPathProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Фон приложения',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (path != null)
          Text(path, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.image_outlined),
              label: const Text('Выбрать обои'),
              onPressed: () async {
                String? p;
                if (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS) {
                  final picked = await ImagePicker()
                      .pickImage(source: ImageSource.gallery);
                  p = picked?.path;
                } else {
                  final f = await openFile(acceptedTypeGroups: const [
                    XTypeGroup(
                      label: 'images',
                      extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
                    ),
                  ]);
                  p = f?.path;
                }
                if (p != null) {
                  await ref.read(wallpaperPathProvider.notifier).set(p);
                }
              },
            ),
            const SizedBox(width: 12),
            if (path != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Убрать'),
                onPressed: () =>
                    ref.read(wallpaperPathProvider.notifier).set(null),
              ),
          ],
        ),
      ],
    );
  }
}

class _AutotestSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = ref.watch(autotestIntervalProvider);
    final minutes = int.tryParse(raw ?? '') ?? 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Авто-проверка серверов',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Каждые N минут пингуется адрес:порт всех профилей, latency '
          'сохраняется в БД и подсвечивается в списке.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                min: 30,
                max: 120,
                divisions: 9,
                value: minutes.toDouble(),
                label: '$minutes мин',
                onChanged: (v) {
                  ref
                      .read(autotestIntervalProvider.notifier)
                      .set(v.toInt().toString());
                },
                onChangeEnd: (v) {
                  ref.read(autotestServiceProvider).configure(
                        interval: Duration(minutes: v.toInt()),
                        preset: ref.read(currentClientPresetProvider),
                      );
                },
              ),
            ),
            Text('$minutes мин'),
          ],
        ),
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.speed),
              label: const Text('Проверить сейчас'),
              onPressed: () => ref.read(autotestServiceProvider).runOnce(),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShareProxySection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ShareProxySection> createState() =>
      _ShareProxySectionState();
}

class _ShareProxySectionState extends ConsumerState<_ShareProxySection> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      _userCtrl.text = ref.read(shareProxyUserProvider) ?? '';
      _passCtrl.text = ref.read(shareProxyPassProvider) ?? '';
      _loaded = true;
    }
    final enabled =
        (ref.watch(shareProxyEnabledProvider) ?? 'false') == 'true';
    final authRaw = ref.watch(shareProxyAuthModeProvider) ?? 'none';
    final svc = ref.watch(lanProxyServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Раздача интернета через VPN (SOCKS5 в LAN)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Запускает встроенный SOCKS5-сервер на 0.0.0.0:1080. Другие '
          'устройства в вашей Wi-Fi/LAN сети могут настроить прокси на ваш '
          'IP:1080, и их трафик пойдёт через активный VPN. Хотспот Wi-Fi '
          'из клиента без системных API ОС невозможен.',
        ),
        const SizedBox(height: 8),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          title: const Text('Без пароля'),
          value: 'none',
          groupValue: authRaw,
          onChanged: (v) =>
              ref.read(shareProxyAuthModeProvider.notifier).set(v),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          title: const Text('user / password (аналог WPA2-Personal)'),
          value: 'userpass',
          groupValue: authRaw,
          onChanged: (v) =>
              ref.read(shareProxyAuthModeProvider.notifier).set(v),
        ),
        if (authRaw == 'userpass') ...[
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: 'user'),
            onChanged: (v) =>
                ref.read(shareProxyUserProvider.notifier).set(v),
          ),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'password'),
            onChanged: (v) =>
                ref.read(shareProxyPassProvider.notifier).set(v),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(enabled
              ? 'Раздача ВКЛЮЧЕНА (порт ${svc.current?.port ?? 1080})'
              : 'Раздача выключена'),
          value: enabled,
          onChanged: (v) async {
            await ref
                .read(shareProxyEnabledProvider.notifier)
                .set(v ? 'true' : 'false');
            if (v) {
              try {
                await svc.start(LanProxyConfig(
                  auth: authRaw == 'userpass'
                      ? LanProxyAuth.userPass
                      : LanProxyAuth.none,
                  user: _userCtrl.text,
                  pass: _passCtrl.text,
                ));
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Не удалось запустить: $e')));
                }
              }
            } else {
              await svc.stop();
            }
            setState(() {});
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}

class _IpVisibilitySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = (ref.watch(showIpProvider) ?? 'true') == 'true';
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Показывать публичный IP на главном экране'),
      value: show,
      onChanged: (v) => ref.read(showIpProvider.notifier).set(v ? 'true' : 'false'),
    );
  }
}
