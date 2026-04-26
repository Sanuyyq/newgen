import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/client_preset.dart';
import 'models/engine_kind.dart';
import 'models/profile.dart';
import 'models/subscription.dart';
import 'services/autotest_service.dart';
import 'services/lan_proxy_service.dart';
import 'services/network_service.dart';
import 'services/subscription_service.dart';
import 'storage/database.dart';

/// Инжектится из main() после инициализации.
final databaseProvider = Provider<NegernDb>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in main()');
});

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final svc = SubscriptionService(ref.watch(databaseProvider));
  // Следим за изменением пресета клиента — подмена User-Agent «на лету».
  ref.listen<ClientPreset>(
    currentClientPresetProvider,
    (_, next) => svc.updatePreset(next),
    fireImmediately: true,
  );
  return svc;
});

/// Триггер перезагрузки списков после мутаций.
final _refreshTick = StateProvider<int>((_) => 0);
void bumpRefresh(WidgetRef ref) =>
    ref.read(_refreshTick.notifier).update((v) => v + 1);

final profilesProvider = FutureProvider.family<List<VpnProfile>, EngineKind>(
  (ref, engine) {
    ref.watch(_refreshTick);
    return ref.watch(databaseProvider).listProfiles(engine);
  },
);

final subscriptionsProvider =
    FutureProvider.family<List<Subscription>, EngineKind>((ref, engine) {
  ref.watch(_refreshTick);
  return ref.watch(databaseProvider).listSubscriptions(engine);
});

/// id выбранного профиля во вкладке (персистится в settings).
class SelectedProfileNotifier extends StateNotifier<int?> {
  SelectedProfileNotifier(this._db, this._key) : super(null) {
    _load();
  }

  final NegernDb _db;
  final String _key;

  Future<void> _load() async {
    final raw = await _db.getSetting(_key);
    if (raw != null) state = int.tryParse(raw);
  }

  Future<void> select(int? id) async {
    state = id;
    await _db.setSetting(_key, id?.toString());
  }
}

final selectedProfileProvider = StateNotifierProvider.family<
    SelectedProfileNotifier, int?, EngineKind>((ref, engine) {
  final db = ref.watch(databaseProvider);
  final key = 'selected_profile_${engine.code}';
  return SelectedProfileNotifier(db, key);
});

/// remoteBuiltinUrl — задаётся в Settings.
class RemoteBuiltinNotifier extends StateNotifier<String?> {
  RemoteBuiltinNotifier(this._db) : super(null) {
    _load();
  }

  final NegernDb _db;
  static const _key = 'remote_builtin_url';

  Future<void> _load() async {
    state = await _db.getSetting(_key);
  }

  Future<void> set(String? url) async {
    state = (url == null || url.isEmpty) ? null : url;
    await _db.setSetting(_key, state);
  }
}

final remoteBuiltinUrlProvider =
    StateNotifierProvider<RemoteBuiltinNotifier, String?>(
        (ref) => RemoteBuiltinNotifier(ref.watch(databaseProvider)));

/// Обобщённый key/value-Notifier, сохраняющий строку в settings.
class SettingNotifier extends StateNotifier<String?> {
  SettingNotifier(this._db, this._key) : super(null) {
    _load();
  }

  final NegernDb _db;
  final String _key;

  Future<void> _load() async {
    state = await _db.getSetting(_key);
  }

  Future<void> set(String? v) async {
    state = (v == null || v.isEmpty) ? null : v;
    await _db.setSetting(_key, state);
  }
}

final clientPresetIdProvider =
    StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'client_preset_id'),
);

final connectionModeProvider =
    StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'connection_mode'),
);

final wallpaperPathProvider =
    StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'wallpaper_path'),
);

/// Показывать ли публичный IP в UI.
final showIpProvider = StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'show_ip'),
);

/// Интервал авто-проверки серверов в минутах (30..120).
final autotestIntervalProvider =
    StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'autotest_minutes'),
);

/// Настройки LAN-раздачи через встроенный SOCKS5.
final shareProxyEnabledProvider =
    StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'share_proxy_enabled'),
);
final shareProxyAuthModeProvider =
    StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'share_proxy_auth'),
);
final shareProxyUserProvider =
    StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'share_proxy_user'),
);
final shareProxyPassProvider =
    StateNotifierProvider<SettingNotifier, String?>(
  (ref) => SettingNotifier(ref.watch(databaseProvider), 'share_proxy_pass'),
);

/// Текущий пресет клиента (объект, не id).
final currentClientPresetProvider = Provider<ClientPreset>((ref) {
  final id = ref.watch(clientPresetIdProvider);
  return ClientPreset.byId(id);
});

final networkServiceProvider = Provider<NetworkService>((_) => NetworkService());

final lanProxyServiceProvider = Provider<LanProxyService>((ref) {
  final svc = LanProxyService();
  ref.onDispose(svc.stop);
  return svc;
});

final autotestServiceProvider = Provider<AutotestService>((ref) {
  final svc = AutotestService(
    ref.watch(databaseProvider),
    ref.watch(networkServiceProvider),
  );
  ref.onDispose(svc.stop);
  return svc;
});
