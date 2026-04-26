import '../models/engine_kind.dart';
import '../models/profile.dart';
import '../models/vpn_status.dart';

/// Абстракция VPN-движка. Каждая реализация знает, как превратить
/// нормализованный профиль в команду для нативного слоя.
abstract class VpnEngine {
  EngineKind get kind;

  /// Собирает payload-конфиг, готовый к отправке в нативный слой (Go).
  Map<String, dynamic> buildNativeConfig(VpnProfile profile);

  /// Валидация профиля до старта.
  void validate(VpnProfile profile);

  /// Поток статуса, специфичный для этого движка (фильтрация по kind).
  Stream<VpnStatus> observe();
}
