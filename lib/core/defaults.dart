import 'models/engine_kind.dart';

/// Подписка по умолчанию, ставится при первом запуске.
/// Контент будет подтянут при первом успешном выходе в сеть.
class DefaultSubscription {
  const DefaultSubscription({
    required this.name,
    required this.url,
    required this.engine,
  });

  final String name;
  final String url;
  final EngineKind engine;
}

/// Whitelist встроенных подписок (предустановленные RKN white-list).
const List<DefaultSubscription> kDefaultSubscriptions = [
  DefaultSubscription(
    name: 'tgflovv · free-white-ru',
    url:
        'https://vpn.tgflovv.ru:8443/free-white-ru/43ec362d-ae87-4b21-a546-ae86be5a86b9',
    engine: EngineKind.vless,
  ),
  DefaultSubscription(
    name: 'tgflovv · free-white',
    url:
        'https://vpn.tgflovv.ru:8443/free-white/43ec362d-ae87-4b21-a546-ae86be5a86b9',
    engine: EngineKind.vless,
  ),
  DefaultSubscription(
    name: 'AirLinkVPN · RKN whitelist',
    url:
        'https://raw.githubusercontent.com/AirLinkVPN1/AirLinkVPN/refs/heads/main/rkn_white_list',
    engine: EngineKind.vless,
  ),
  DefaultSubscription(
    name: 'zieng2 · VLESS universal',
    url:
        'https://raw.githubusercontent.com/zieng2/wl/refs/heads/main/vless_universal.txt',
    engine: EngineKind.vless,
  ),
  DefaultSubscription(
    name: 'Temnuk · whitelist (full)',
    url:
        'https://raw.githubusercontent.com/Temnuk/naabuzil/refs/heads/main/whitelist_full',
    engine: EngineKind.vless,
  ),
  DefaultSubscription(
    name: 'Temnuk · whitelist',
    url:
        'https://raw.githubusercontent.com/Temnuk/naabuzil/refs/heads/main/whitelist',
    engine: EngineKind.vless,
  ),
];
