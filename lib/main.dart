import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/engines/session_manager.dart';
import 'core/providers.dart';
import 'core/services/lan_proxy_service.dart';
import 'core/storage/database.dart';
import 'platform/platform_vpn_host.dart';
import 'platform/vpn_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await NegernDb.initialize();

  // Пытаемся связаться с нативным VPN-хостом. В текущей итерации ни на одной
  // платформе он ещё не реализован полностью — падаем на MockVpnHost, чтобы
  // UI-скелет был полностью кликабельным.
  final native = kIsWeb ? false : await PlatformVpnHost.probe();
  final VpnHost host = native ? PlatformVpnHost() : MockVpnHost();

  // Оживляем remoteBuiltinUrl на старте (best-effort, молча игнорируем ошибки).
  final remoteUrl = await db.getSetting('remote_builtin_url');

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(db),
    vpnHostProvider.overrideWithValue(host),
  ]);

  if (remoteUrl != null && remoteUrl.isNotEmpty) {
    // fire-and-forget
    // ignore: unawaited_futures
    container
        .read(subscriptionServiceProvider)
        .syncRemoteBuiltin(url: remoteUrl)
        .catchError((_) {});
  }

  // Авто-проверка серверов (URL/tcp ping). Интервал берём из настроек.
  final minutesRaw = await db.getSetting('autotest_minutes');
  final minutes = int.tryParse(minutesRaw ?? '') ?? 60;
  final autotest = container.read(autotestServiceProvider);
  autotest.configure(
    interval: Duration(minutes: minutes),
    preset: container.read(currentClientPresetProvider),
  );
  autotest.start();

  // Если пользователь раньше включал LAN-раздачу — поднимаем её.
  final shareOn = await db.getSetting('share_proxy_enabled');
  if (shareOn == 'true') {
    // ignore: unawaited_futures
    container.read(lanProxyServiceProvider).start(LanProxyConfig(
          auth: (await db.getSetting('share_proxy_auth')) == 'userpass'
              ? LanProxyAuth.userPass
              : LanProxyAuth.none,
          user: await db.getSetting('share_proxy_user'),
          pass: await db.getSetting('share_proxy_pass'),
        ));
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const NegernApp(),
  ));
}
