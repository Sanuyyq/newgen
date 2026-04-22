import 'package:dio/dio.dart';

import '../models/client_preset.dart';
import '../models/engine_kind.dart';
import '../models/profile.dart';
import '../models/subscription.dart';
import '../parsing/awg_parser.dart';
import '../parsing/subscription_parser.dart';
import '../parsing/vless_parser.dart';
import '../storage/database.dart';

class SubscriptionImportResult {
  SubscriptionImportResult(this.subscription, this.profiles);
  final Subscription subscription;
  final List<VpnProfile> profiles;
}

/// Сервис импорта и обновления подписок.
///
/// Источники:
/// - URL (скачиваем Dio → парсим SubscriptionParser);
/// - вставленный текст (та же логика);
/// - QR-код (декодирован на уровне UI, сюда приходит как текст).
class SubscriptionService {
  SubscriptionService(this._db, {Dio? dio}) : _dio = dio ?? Dio();

  final NegernDb _db;
  final Dio _dio;

  /// Ручной ввод: один URI или один .conf.
  Future<SubscriptionImportResult> importManual({
    required EngineKind engine,
    required String text,
    String? nameOverride,
  }) async {
    final trimmed = text.trim();
    final profiles = <VpnProfile>[];

    if (engine == EngineKind.vless) {
      final parsed = VlessParser.parse(trimmed);
      profiles.add(VpnProfile(
        engine: EngineKind.vless,
        name: nameOverride ?? parsed.name,
        config: parsed.config,
      ));
    } else {
      final parsed = AwgParser.parse(trimmed, fallbackName: nameOverride);
      profiles.add(VpnProfile(
        engine: EngineKind.awg,
        name: nameOverride ?? parsed.name,
        config: parsed.config,
      ));
    }

    final sub = Subscription(
      engine: engine,
      name: nameOverride ?? profiles.first.name,
      source: SubscriptionSource.manual,
      rawPayload: trimmed,
      lastUpdated: DateTime.now(),
    );
    final subId = await _db.insertSubscription(sub);
    await _db.replaceSubscriptionProfiles(subId,
        profiles.map((p) => p.copyWith()).toList(growable: false));
    final stored = await _db.listProfiles(engine);
    return SubscriptionImportResult(
      Subscription(
        id: subId,
        engine: sub.engine,
        name: sub.name,
        source: sub.source,
        url: sub.url,
        rawPayload: sub.rawPayload,
        lastUpdated: sub.lastUpdated,
        autoUpdate: sub.autoUpdate,
      ),
      stored.where((p) => p.subscriptionId == subId).toList(),
    );
  }

  /// Импорт из QR (UI уже распознал в строку).
  Future<SubscriptionImportResult> importFromQr({
    required EngineKind engine,
    required String payload,
    String? nameOverride,
  }) async {
    final res = await importManual(
      engine: engine,
      text: payload,
      nameOverride: nameOverride,
    );
    return res;
  }

  /// Подписка через URL (base64-список или plain).
  Future<SubscriptionImportResult> importUrl({
    required EngineKind engine,
    required String url,
    String? nameOverride,
  }) async {
    final body = await _fetch(url);
    final profiles = SubscriptionParser.parse(body)
        .where((p) => p.engine == engine)
        .toList();
    if (profiles.isEmpty) {
      throw StateError('No ${engine.label} profiles found in subscription');
    }

    final subId = await _db.insertSubscription(Subscription(
      engine: engine,
      name: nameOverride ?? Uri.parse(url).host,
      source: SubscriptionSource.url,
      url: url,
      rawPayload: body,
      lastUpdated: DateTime.now(),
      autoUpdate: true,
    ));
    await _db.replaceSubscriptionProfiles(subId, profiles);

    final all = await _db.listSubscriptions(engine);
    final created = all.firstWhere((s) => s.id == subId);
    final stored = await _db.listProfiles(engine);
    return SubscriptionImportResult(
      created,
      stored.where((p) => p.subscriptionId == subId).toList(),
    );
  }

  /// Перезагрузить существующую URL-подписку.
  Future<void> refresh(Subscription sub) async {
    final url = sub.url;
    if (url == null || sub.id == null) return;
    final body = await _fetch(url);
    final profiles = SubscriptionParser.parse(body)
        .where((p) => p.engine == sub.engine)
        .toList();
    await _db.replaceSubscriptionProfiles(sub.id!, profiles);
    await _db.touchSubscription(sub.id!,
        lastUpdated: DateTime.now(), rawPayload: body);
  }

  /// Подтянуть remote builtin по URL из настроек; merge как отдельную подписку.
  Future<void> syncRemoteBuiltin({required String url}) async {
    final body = await _fetch(url);
    // Ожидаем тот же формат, что assets/builtin_profiles.json — либо как
    // обычную подписку. Здесь трактуем как подписку (vless://... / .conf).
    for (final engine in EngineKind.values) {
      final profiles = SubscriptionParser.parse(body)
          .where((p) => p.engine == engine)
          .toList();
      if (profiles.isEmpty) continue;
      final existing = await _db.listSubscriptions(engine);
      final slot = existing.where(
        (s) => s.source == SubscriptionSource.remoteBuiltin,
      );
      int subId;
      if (slot.isEmpty) {
        subId = await _db.insertSubscription(Subscription(
          engine: engine,
          name: 'Remote builtin',
          source: SubscriptionSource.remoteBuiltin,
          url: url,
          rawPayload: body,
          lastUpdated: DateTime.now(),
        ));
      } else {
        subId = slot.first.id!;
        await _db.touchSubscription(subId,
            lastUpdated: DateTime.now(), rawPayload: body);
      }
      await _db.replaceSubscriptionProfiles(subId, profiles);
    }
  }

  Future<String> _fetch(String url) async {
    final resp = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {'User-Agent': _preset.userAgent},
      ),
    );
    return resp.data ?? '';
  }
}
