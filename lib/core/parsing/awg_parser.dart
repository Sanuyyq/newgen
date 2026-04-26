/// Парсер AmneziaWG .conf (INI-формат) с поддержкой AWG 1.5-параметров:
/// Jc, Jmin, Jmax, S1, S2, H1..H4.
class AwgParseException implements Exception {
  AwgParseException(this.message);
  final String message;
  @override
  String toString() => 'AwgParseException: $message';
}

class ParsedAwg {
  ParsedAwg({required this.name, required this.config});
  final String name;
  final Map<String, dynamic> config;
}

class AwgParser {
  static ParsedAwg parse(String raw, {String? fallbackName}) {
    final sections = <String, Map<String, String>>{};
    String? current;
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#') || trimmed.startsWith(';')) continue;
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        current = trimmed.substring(1, trimmed.length - 1).trim();
        sections[current] ??= {};
        continue;
      }
      final eq = trimmed.indexOf('=');
      if (eq < 0 || current == null) continue;
      final key = trimmed.substring(0, eq).trim();
      final value = trimmed.substring(eq + 1).trim();
      sections[current]![key] = value;
    }

    final iface = sections['Interface'];
    final peer = sections['Peer'];
    if (iface == null) throw AwgParseException('Missing [Interface] section');
    if (peer == null) throw AwgParseException('Missing [Peer] section');

    String? get(Map<String, String> m, String key) {
      // Case-insensitive lookup.
      for (final e in m.entries) {
        if (e.key.toLowerCase() == key.toLowerCase()) return e.value;
      }
      return null;
    }

    int? asInt(String? v) => v == null ? null : int.tryParse(v);

    final pk = get(iface, 'PrivateKey');
    if (pk == null || pk.isEmpty) {
      throw AwgParseException('Missing Interface.PrivateKey');
    }
    final peerPub = get(peer, 'PublicKey');
    if (peerPub == null || peerPub.isEmpty) {
      throw AwgParseException('Missing Peer.PublicKey');
    }
    final endpoint = get(peer, 'Endpoint');
    if (endpoint == null || endpoint.isEmpty) {
      throw AwgParseException('Missing Peer.Endpoint');
    }

    final config = <String, dynamic>{
      'privateKey': pk,
      'address': get(iface, 'Address') ?? '',
      'dns': (get(iface, 'DNS') ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'mtu': asInt(get(iface, 'MTU')) ?? 1420,
      if (asInt(get(iface, 'Jc')) != null) 'jc': asInt(get(iface, 'Jc')),
      if (asInt(get(iface, 'Jmin')) != null) 'jmin': asInt(get(iface, 'Jmin')),
      if (asInt(get(iface, 'Jmax')) != null) 'jmax': asInt(get(iface, 'Jmax')),
      if (asInt(get(iface, 'S1')) != null) 's1': asInt(get(iface, 'S1')),
      if (asInt(get(iface, 'S2')) != null) 's2': asInt(get(iface, 'S2')),
      if (asInt(get(iface, 'H1')) != null) 'h1': asInt(get(iface, 'H1')),
      if (asInt(get(iface, 'H2')) != null) 'h2': asInt(get(iface, 'H2')),
      if (asInt(get(iface, 'H3')) != null) 'h3': asInt(get(iface, 'H3')),
      if (asInt(get(iface, 'H4')) != null) 'h4': asInt(get(iface, 'H4')),
      'peer': {
        'publicKey': peerPub,
        'presharedKey': get(peer, 'PresharedKey') ?? '',
        'endpoint': endpoint,
        'allowedIPs': (get(peer, 'AllowedIPs') ?? '0.0.0.0/0')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        if (asInt(get(peer, 'PersistentKeepalive')) != null)
          'persistentKeepalive': asInt(get(peer, 'PersistentKeepalive')),
      },
    };

    final name = fallbackName ?? _hostFromEndpoint(endpoint);
    return ParsedAwg(name: name, config: config);
  }

  static String _hostFromEndpoint(String endpoint) {
    final lastColon = endpoint.lastIndexOf(':');
    if (lastColon <= 0) return endpoint;
    return endpoint.substring(0, lastColon);
  }
}
