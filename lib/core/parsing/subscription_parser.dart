import 'dart:convert';

import '../models/engine_kind.dart';
import '../models/profile.dart';
import 'awg_parser.dart';
import 'vless_parser.dart';

/// Разбирает тело подписки: base64 → текст → список строк.
/// Каждая строка: либо `vless://...`, либо отдельный .conf (редкий кейс).
class SubscriptionParser {
  /// Декодирует body подписки в список профилей.
  ///
  /// Форматы:
  /// - base64 всего тела (каноничный формат v2ray-подписок);
  /// - plain text, по одному URI на строку;
  /// - один `.conf` (AWG) целиком.
  static List<VpnProfile> parse(String body, {int? subscriptionId}) {
    final text = _maybeDecodeBase64(body);
    final out = <VpnProfile>[];

    // Пробуем как AWG-конфиг, если есть [Interface] / [Peer].
    if (text.contains('[Interface]') && text.contains('[Peer]')) {
      try {
        final awg = AwgParser.parse(text);
        out.add(VpnProfile(
          subscriptionId: subscriptionId,
          engine: EngineKind.awg,
          name: awg.name,
          config: awg.config,
        ));
        return out;
      } catch (_) {
        // fallthrough — попробуем как список URI
      }
    }

    for (final line in text.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('vless://')) {
        try {
          final p = VlessParser.parse(t);
          out.add(VpnProfile(
            subscriptionId: subscriptionId,
            engine: EngineKind.vless,
            name: p.name,
            config: p.config,
          ));
        } catch (_) {
          // ignore bad line
        }
      }
      // Сюда позже могут добавиться vmess://, ss:// и т.п.
    }
    return out;
  }

  static String _maybeDecodeBase64(String body) {
    final s = body.trim();
    // Быстрая эвристика: если строка состоит только из base64-символов
    // и длина кратна 4 (или почти) — пробуем декодировать.
    final normalized = s.replaceAll(RegExp(r'\s+'), '');
    final looksBase64 = RegExp(r'^[A-Za-z0-9+/_\-=]+$').hasMatch(normalized) &&
        normalized.length > 16;
    if (!looksBase64) return s;
    try {
      // Поддержка url-safe base64.
      final padded = normalized.padRight(
        normalized.length + (4 - normalized.length % 4) % 4,
        '=',
      );
      final bytes = base64.decode(padded.replaceAll('-', '+').replaceAll('_', '/'));
      final decoded = utf8.decode(bytes, allowMalformed: true);
      // Если внутри есть vless:// — почти наверняка это подписка.
      if (decoded.contains('vless://') || decoded.contains('[Interface]')) {
        return decoded;
      }
    } catch (_) {}
    return s;
  }
}
