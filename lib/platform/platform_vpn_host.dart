import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/models/engine_kind.dart';
import '../core/models/vpn_status.dart';
import 'vpn_host.dart';

/// VpnHost, ходящий через MethodChannel/EventChannel в нативный слой.
/// Если на текущей платформе нативный плагин ещё не зарегистрирован
/// (MissingPluginException), вызывающий код должен использовать [MockVpnHost].
class PlatformVpnHost implements VpnHost {
  PlatformVpnHost();

  static const _method = MethodChannel('negern/vpn');
  static const _events = EventChannel('negern/vpn/events');

  Stream<VpnStatus>? _statusStream;

  @override
  Future<bool> prepare() async {
    final ok = await _method.invokeMethod<bool>('prepare');
    return ok ?? false;
  }

  @override
  Future<void> start({
    required EngineKind engine,
    required Map<String, dynamic> config,
    Map<String, dynamic>? routing,
  }) async {
    await _method.invokeMethod<void>('start', {
      'engine': engine.code,
      'configJson': jsonEncode(config),
      'routingJson': jsonEncode(routing ?? const {}),
    });
  }

  @override
  Future<void> stop() => _method.invokeMethod<void>('stop');

  @override
  Future<VpnStatus> status() async {
    final raw = await _method.invokeMethod<Map<dynamic, dynamic>>('status');
    return _decode(raw ?? const {});
  }

  @override
  Stream<VpnStatus> statusStream() {
    _statusStream ??= _events.receiveBroadcastStream().map((e) {
      if (e is Map) return _decode(e);
      return const VpnStatus();
    });
    return _statusStream!;
  }

  VpnStatus _decode(Map<dynamic, dynamic> raw) {
    final stateStr = (raw['state'] as String?) ?? 'disconnected';
    final engineCode = raw['engine'] as int?;
    return VpnStatus(
      state: VpnState.values.firstWhere(
        (s) => s.name == stateStr,
        orElse: () => VpnState.disconnected,
      ),
      engine: engineCode == null ? null : EngineKind.fromCode(engineCode),
      uploadBytes: (raw['upload'] as int?) ?? 0,
      downloadBytes: (raw['download'] as int?) ?? 0,
      errorMessage: raw['error'] as String?,
    );
  }

  /// Проверяет, отвечает ли нативная сторона. Если нет — возвращает false,
  /// и приложение должно переключиться на MockVpnHost.
  static Future<bool> probe() async {
    try {
      await _method.invokeMethod<Map<dynamic, dynamic>>('status');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      // Канал есть, но реализация недоделана — считаем живым.
      return true;
    } catch (_) {
      return false;
    }
  }
}
