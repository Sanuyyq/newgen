/// Пресет «клиент», под который мы маскируемся. Влияет на:
/// - `fingerprint` в RealitySettings (fp),
/// - User-Agent при скачивании подписок,
/// - опционально `spiderX` и другие RU-специфичные поля.
///
/// Используется серверами, принимающими трафик только от Happ/NekoBox/…
class ClientPreset {
  const ClientPreset({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.userAgent,
    this.spiderX = '',
  });

  final String id;
  final String name;
  final String fingerprint; // chrome / firefox / safari / ios / android / edge / random
  final String userAgent;
  final String spiderX;

  static const happ = ClientPreset(
    id: 'happ',
    name: 'Happ',
    fingerprint: 'chrome',
    userAgent:
        'Happ/1.10.0 (com.happproxy; build:110; iOS 17.5.1) Alamofire/5.9.1',
  );
  static const nekoBox = ClientPreset(
    id: 'nekobox',
    name: 'NekoBox',
    fingerprint: 'firefox',
    userAgent: 'NekoBox/1.3.8',
  );
  static const v2rayN = ClientPreset(
    id: 'v2rayn',
    name: 'v2rayN',
    fingerprint: 'chrome',
    userAgent: 'v2rayN/6.46',
  );
  static const xrayCore = ClientPreset(
    id: 'xray',
    name: 'Xray-core',
    fingerprint: 'chrome',
    userAgent: 'Xray/1.8.24',
  );
  static const hiddify = ClientPreset(
    id: 'hiddify',
    name: 'Hiddify',
    fingerprint: 'safari',
    userAgent: 'Hiddify/2.0.5',
  );
  static const negern = ClientPreset(
    id: 'negern',
    name: 'Negern (сам)',
    fingerprint: 'chrome',
    userAgent: 'Negern/0.1.0',
  );

  static const all = <ClientPreset>[
    happ,
    nekoBox,
    v2rayN,
    xrayCore,
    hiddify,
    negern,
  ];

  static ClientPreset byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return negern;
  }
}

enum ConnectionMode {
  tun('TUN (перехват всего трафика)'),
  proxy('Локальный SOCKS/HTTP прокси');

  final String label;
  const ConnectionMode(this.label);
}
