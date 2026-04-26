import '../models/engine_kind.dart';
import '../models/profile.dart';
import '../parsing/vless_parser.dart';

class ExportService {
  /// Собрать список vless:// ссылок из профилей (только VLESS).
  static List<String> toVlessLinks(List<VpnProfile> profiles) {
    final out = <String>[];
    for (final p in profiles) {
      if (p.engine != EngineKind.vless) continue;
      try {
        out.add(VlessParser.build(name: p.name, c: p.config));
      } catch (_) {}
    }
    return out;
  }

  /// AWG-профили в виде .conf-текстов.
  static List<String> toAwgConfs(List<VpnProfile> profiles) {
    final out = <String>[];
    for (final p in profiles) {
      if (p.engine != EngineKind.awg) continue;
      out.add(_awgToIni(p));
    }
    return out;
  }

  static String _awgToIni(VpnProfile p) {
    final c = p.config;
    final peer = (c['peer'] as Map?) ?? const {};
    final sb = StringBuffer();
    sb.writeln('# ${p.name}');
    sb.writeln('[Interface]');
    sb.writeln('PrivateKey = ${c['privateKey']}');
    if ((c['address'] ?? '').toString().isNotEmpty) {
      sb.writeln('Address = ${c['address']}');
    }
    if (c['dns'] is List && (c['dns'] as List).isNotEmpty) {
      sb.writeln('DNS = ${(c['dns'] as List).join(", ")}');
    }
    if (c['mtu'] != null) sb.writeln('MTU = ${c['mtu']}');
    for (final k in ['jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4']) {
      if (c[k] != null) sb.writeln('${k.toUpperCase()} = ${c[k]}');
    }
    sb.writeln();
    sb.writeln('[Peer]');
    sb.writeln('PublicKey = ${peer['publicKey']}');
    if ((peer['presharedKey'] ?? '').toString().isNotEmpty) {
      sb.writeln('PresharedKey = ${peer['presharedKey']}');
    }
    sb.writeln('Endpoint = ${peer['endpoint']}');
    final allowed = peer['allowedIPs'];
    if (allowed is List) {
      sb.writeln('AllowedIPs = ${allowed.join(", ")}');
    }
    if (peer['persistentKeepalive'] != null) {
      sb.writeln('PersistentKeepalive = ${peer['persistentKeepalive']}');
    }
    return sb.toString();
  }
}
