import 'engine_kind.dart';

/// Универсальный профиль. Конкретные поля движка лежат в [configJson]
/// в нормализованном виде (см. `parsers/`).
class VpnProfile {
  final int? id;
  final int? subscriptionId;
  final EngineKind engine;
  final String name;
  final String? remark;
  final Map<String, dynamic> config;
  final bool isBuiltin;
  final List<String> tags;
  final int? latencyMs;
  final DateTime? lastUsedAt;

  const VpnProfile({
    this.id,
    this.subscriptionId,
    required this.engine,
    required this.name,
    required this.config,
    this.remark,
    this.isBuiltin = false,
    this.tags = const [],
    this.latencyMs,
    this.lastUsedAt,
  });

  VpnProfile copyWith({
    int? id,
    String? name,
    Map<String, dynamic>? config,
    int? latencyMs,
    DateTime? lastUsedAt,
  }) =>
      VpnProfile(
        id: id ?? this.id,
        subscriptionId: subscriptionId,
        engine: engine,
        name: name ?? this.name,
        remark: remark,
        config: config ?? this.config,
        isBuiltin: isBuiltin,
        tags: tags,
        latencyMs: latencyMs ?? this.latencyMs,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );
}
