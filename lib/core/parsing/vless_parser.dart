/// Парсер ссылок вида `vless://uuid@host:port?param=value#name`.
///
/// Возвращает нормализованную Map<String, dynamic>, совместимую с
/// `VpnProfile.config` (см. assets/builtin_profiles.json).
class VlessParseException implements Exception {
  VlessParseException(this.message);
  final String message;
  @override
  String toString() => 'VlessParseException: $message';
}

class ParsedVless {
  ParsedVless({required this.name, required this.config});
  final String name;
  final Map<String, dynamic> config;
}

class VlessParser {
  static const _scheme = 'vless://';

  /// Бросает [VlessParseException] при несоответствии формату.
  static ParsedVless parse(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(_scheme)) {
      throw VlessParseException('URI must start with vless://');
    }

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      throw VlessParseException('Invalid URI');
    }

    final uuid = Uri.decodeComponent(uri.userInfo);
    if (uuid.isEmpty) throw VlessParseException('Missing UUID');

    final host = uri.host;
    if (host.isEmpty) throw VlessParseException('Missing host');

    final port = uri.hasPort ? uri.port : 443;
    final q = uri.queryParameters;

    final name = uri.fragment.isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : '$host:$port';

    final config = <String, dynamic>{
      'address': host,
      'port': port,
      'uuid': uuid,
      'flow': q['flow'] ?? '',
      'security': q['security'] ?? 'none',
      'type': q['type'] ?? 'tcp',
      if (q['sni'] != null && q['sni']!.isNotEmpty) 'sni': q['sni'],
      if (q['fp'] != null && q['fp']!.isNotEmpty) 'fp': q['fp'],
      if (q['pbk'] != null && q['pbk']!.isNotEmpty) 'pbk': q['pbk'],
      if (q['sid'] != null) 'sid': q['sid'],
      if (q['spx'] != null && q['spx']!.isNotEmpty) 'spx': q['spx'],
      if (q['host'] != null && q['host']!.isNotEmpty) 'wsHost': q['host'],
      if (q['path'] != null && q['path']!.isNotEmpty) 'wsPath': q['path'],
      if (q['alpn'] != null && q['alpn']!.isNotEmpty) 'alpn': q['alpn'],
      if (q['encryption'] != null) 'encryption': q['encryption'],
    };

    return ParsedVless(name: name, config: config);
  }

  /// Собрать vless:// из нормализованного конфига (для QR-шаринга).
  static String build({required String name, required Map<String, dynamic> c}) {
    final params = <String, String>{
      if ((c['security'] ?? '') != '') 'security': '${c['security']}',
      if ((c['type'] ?? '') != '') 'type': '${c['type']}',
      if ((c['flow'] ?? '') != '') 'flow': '${c['flow']}',
      if ((c['sni'] ?? '') != '') 'sni': '${c['sni']}',
      if ((c['fp'] ?? '') != '') 'fp': '${c['fp']}',
      if ((c['pbk'] ?? '') != '') 'pbk': '${c['pbk']}',
      if ((c['sid'] ?? '') != '') 'sid': '${c['sid']}',
      if ((c['spx'] ?? '') != '') 'spx': '${c['spx']}',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final uuid = Uri.encodeComponent('${c['uuid']}');
    final host = c['address'];
    final port = c['port'];
    final frag = Uri.encodeComponent(name);
    return 'vless://$uuid@$host:$port?$query#$frag';
  }
}
