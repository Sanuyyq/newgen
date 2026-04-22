import 'dart:async';

import '../core/models/engine_kind.dart';
import '../core/models/vpn_status.dart';

/// Абстракция хоста VPN: либо нативная реализация (MethodChannel → VpnService / C++),
/// либо in-process мок (для dev/Windows без elevation).
abstract class VpnHost {
  Future<bool> prepare();

  Future<void> start({
    required EngineKind engine,
    required Map<String, dynamic> config,
    Map<String, dynamic>? routing,
  });

  Future<void> stop();

  Future<VpnStatus> status();

  Stream<VpnStatus> statusStream();
}

/// In-process мок: эмулирует подключение (connecting → connected) и счётчики
/// трафика по таймеру. Используется, если нативный канал недоступен.
class MockVpnHost implements VpnHost {
  final _controller = StreamController<VpnStatus>.broadcast();
  VpnStatus _current = const VpnStatus();
  Timer? _trafficTimer;

  VpnStatus get current => _current;

  @override
  Future<bool> prepare() async => true;

  @override
  Future<void> start({
    required EngineKind engine,
    required Map<String, dynamic> config,
    Map<String, dynamic>? routing,
  }) async {
    _emit(VpnStatus(state: VpnState.connecting, engine: engine));
    await Future.delayed(const Duration(milliseconds: 450));
    _emit(VpnStatus(state: VpnState.connected, engine: engine));
    _startTrafficEmulation(engine);
  }

  @override
  Future<void> stop() async {
    _trafficTimer?.cancel();
    _trafficTimer = null;
    _emit(VpnStatus(state: VpnState.disconnecting, engine: _current.engine));
    await Future.delayed(const Duration(milliseconds: 200));
    _emit(const VpnStatus());
  }

  @override
  Future<VpnStatus> status() async => _current;

  @override
  Stream<VpnStatus> statusStream() => _controller.stream;

  void _emit(VpnStatus s) {
    _current = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  void _startTrafficEmulation(EngineKind engine) {
    _trafficTimer?.cancel();
    var up = 0;
    var down = 0;
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      up += 1200 + (DateTime.now().millisecond % 500);
      down += 4800 + (DateTime.now().millisecond % 2000);
      _emit(VpnStatus(
        state: VpnState.connected,
        engine: engine,
        uploadBytes: up,
        downloadBytes: down,
      ));
    });
  }

  void dispose() {
    _trafficTimer?.cancel();
    _controller.close();
  }
}
