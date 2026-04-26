import '../models/client_preset.dart';
import '../models/engine_kind.dart';
import '../models/profile.dart';
import '../models/vpn_status.dart';
import 'vpn_engine.dart';

class XrayEngine implements VpnEngine {
  XrayEngine({this.preset = ClientPreset.negern, this.mode = ConnectionMode.tun});

  final ClientPreset preset;
  final ConnectionMode mode;

  @override
  EngineKind get kind => EngineKind.vless;

  @override
  void validate(VpnProfile profile) {
    final c = profile.config;
    if (c['address'] == null || c['port'] == null || c['uuid'] == null) {
      throw ArgumentError('VLESS profile missing required fields');
    }
  }

  @override
  Map<String, dynamic> buildNativeConfig(VpnProfile profile) {
    final c = profile.config;
    // Пресет клиента: подменяем fingerprint и spiderX, если они не заданы явно.
    final fp = (c['fp'] as String?)?.isNotEmpty == true
        ? c['fp']
        : preset.fingerprint;
    final spx = (c['spx'] as String?)?.isNotEmpty == true
        ? c['spx']
        : preset.spiderX;
    // Inbound зависит от выбранного режима: TUN (перехват всего) vs Proxy.
    final inbound = mode == ConnectionMode.tun
        ? {
            'tag': 'tun-in',
            'protocol': 'dokodemo-door',
            'settings': {'network': 'tcp,udp', 'followRedirect': true},
            'sniffing': {
              'enabled': true,
              'destOverride': ['http', 'tls'],
            },
          }
        : {
            'tag': 'socks-in',
            'port': 10808,
            'listen': '127.0.0.1',
            'protocol': 'socks',
            'settings': {'udp': true, 'auth': 'noauth'},
          };
    return {
      'log': {'loglevel': 'warning'},
      'clientPreset': preset.id,
      'connectionMode': mode.name,
      'inbounds': [inbound],
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': c['address'],
                'port': c['port'],
                'users': [
                  {
                    'id': c['uuid'],
                    'encryption': 'none',
                    'flow': c['flow'] ?? 'xtls-rprx-vision',
                  }
                ]
              }
            ]
          },
          'streamSettings': {
            'network': c['type'] ?? 'tcp',
            'security': c['security'] ?? 'reality',
            'realitySettings': {
              'serverName': c['sni'],
              'fingerprint': fp,
              'publicKey': c['pbk'],
              'shortId': c['sid'] ?? '',
              'spiderX': spx,
            }
          }
        },
        {'tag': 'direct', 'protocol': 'freedom'},
      ],
    };
  }

  @override
  Stream<VpnStatus> observe() => const Stream<VpnStatus>.empty();
}
