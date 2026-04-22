import 'engine_kind.dart';

enum VpnState { disconnected, connecting, connected, disconnecting, error }

class VpnStatus {
  final VpnState state;
  final EngineKind? engine;
  final int uploadBytes;
  final int downloadBytes;
  final String? errorMessage;

  const VpnStatus({
    this.state = VpnState.disconnected,
    this.engine,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.errorMessage,
  });

  bool get isActive =>
      state == VpnState.connected || state == VpnState.connecting;
}
