import 'dart:async';

import '../models/client_preset.dart';
import '../models/engine_kind.dart';
import '../models/profile.dart';
import '../storage/database.dart';
import 'network_service.dart';

/// Периодически пингует серверы всех профилей и сохраняет latency_ms в БД.
///
/// Интервал настраивается пользователем в Settings (30..120 минут).
class AutotestService {
  AutotestService(this._db, this._net);
  final NegernDb _db;
  final NetworkService _net;

  Timer? _timer;
  bool _running = false;
  Duration _interval = const Duration(hours: 1);
  ClientPreset _preset = ClientPreset.negern;

  void configure({required Duration interval, required ClientPreset preset}) {
    _interval = interval.inMinutes < 30
        ? const Duration(minutes: 30)
        : (interval.inMinutes > 120
            ? const Duration(hours: 2)
            : interval);
    _preset = preset;
    if (_timer != null) {
      restart();
    }
  }

  ClientPreset get preset => _preset;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => runOnce());
    // Первый прогон сразу, чтобы не ждать полный интервал.
    Future<void>.delayed(const Duration(seconds: 5), runOnce);
  }

  void restart() {
    start();
  }

  Future<void> runOnce() async {
    if (_running) return;
    _running = true;
    try {
      for (final engine in EngineKind.values) {
        final profiles = await _db.listProfiles(engine);
        for (final p in profiles) {
          final host = _hostFor(p);
          final port = _portFor(p);
          if (host == null || port == null) continue;
          final ping = await _net.tcpPing(host, port);
          await _db.updateProfileLatency(p.id!, ping.ok ? ping.ms : null);
        }
      }
    } finally {
      _running = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  String? _hostFor(VpnProfile p) {
    if (p.engine == EngineKind.vless) return p.config['address'] as String?;
    final peer = p.config['peer'] as Map?;
    final endpoint = peer?['endpoint'] as String?;
    if (endpoint == null) return null;
    final i = endpoint.lastIndexOf(':');
    return i > 0 ? endpoint.substring(0, i) : endpoint;
  }

  int? _portFor(VpnProfile p) {
    if (p.engine == EngineKind.vless) {
      final port = p.config['port'];
      return port is int ? port : int.tryParse('$port');
    }
    final peer = p.config['peer'] as Map?;
    final endpoint = peer?['endpoint'] as String?;
    if (endpoint == null) return null;
    final i = endpoint.lastIndexOf(':');
    return i > 0 ? int.tryParse(endpoint.substring(i + 1)) : null;
  }
}
