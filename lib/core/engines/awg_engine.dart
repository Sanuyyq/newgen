import '../models/engine_kind.dart';
import '../models/profile.dart';
import '../models/vpn_status.dart';
import 'vpn_engine.dart';

class AwgEngine implements VpnEngine {
  @override
  EngineKind get kind => EngineKind.awg;

  @override
  void validate(VpnProfile profile) {
    final c = profile.config;
    if (c['privateKey'] == null || c['peer'] == null) {
      throw ArgumentError('AWG profile missing required fields');
    }
  }

  @override
  Map<String, dynamic> buildNativeConfig(VpnProfile profile) {
    final c = profile.config;
    final peer = c['peer'] as Map<String, dynamic>;
    // Нормализованный JSON, который Go-мост превратит в UAPI-строку для amneziawg-go.
    return {
      'interface': {
        'privateKey': c['privateKey'],
        'address': c['address'],
        'dns': c['dns'] ?? const ['1.1.1.1'],
        'mtu': c['mtu'] ?? 1420,
        // AWG 1.5 параметры обфускации
        'jc': c['jc'],
        'jmin': c['jmin'],
        'jmax': c['jmax'],
        's1': c['s1'],
        's2': c['s2'],
        'h1': c['h1'],
        'h2': c['h2'],
        'h3': c['h3'],
        'h4': c['h4'],
      },
      'peer': {
        'publicKey': peer['publicKey'],
        'presharedKey': peer['presharedKey'],
        'endpoint': peer['endpoint'],
        'allowedIPs': peer['allowedIPs'] ?? const ['0.0.0.0/0'],
        'persistentKeepalive': peer['persistentKeepalive'] ?? 25,
      },
    };
  }

  @override
  Stream<VpnStatus> observe() => const Stream<VpnStatus>.empty();
}
