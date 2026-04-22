import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/platform_vpn_host.dart';
import '../../platform/vpn_host.dart';
import '../models/client_preset.dart';
import '../models/engine_kind.dart';
import '../models/profile.dart';
import '../models/vpn_status.dart';
import '../providers.dart';
import '../storage/database.dart';
import 'awg_engine.dart';
import 'vpn_engine.dart';
import 'xray_engine.dart';

/// Единая точка управления VPN-сессией. Гарантирует, что в любой момент
/// работает максимум один движок (правило "жёсткого switch").
class VpnSessionManager {
  VpnSessionManager(
    this._host, {
    this.preset = ClientPreset.negern,
    this.mode = ConnectionMode.tun,
    this.db,
  });

  final VpnHost _host;
  VpnHost get host => _host;
  final ClientPreset preset;
  final ConnectionMode mode;
  final NegernDb? db;

  late final XrayEngine _xray = XrayEngine(preset: preset, mode: mode);
  final AwgEngine _awg = AwgEngine();

  int? _activeLogId;

  VpnEngine engineFor(EngineKind k) => switch (k) {
        EngineKind.vless => _xray,
        EngineKind.awg => _awg,
      };

  Future<void> connect(VpnProfile profile,
      {Map<String, dynamic>? routing}) async {
    final engine = engineFor(profile.engine);
    engine.validate(profile);

    final current = await _host.status();
    if (current.isActive && current.engine != profile.engine) {
      await _host.stop();
      await _waitFor(VpnState.disconnected);
      await _finishLog();
    }

    await _host.prepare();
    final native = engine.buildNativeConfig(profile);
    try {
      await _host.start(
        engine: profile.engine,
        config: native,
        routing: routing,
      );
      _activeLogId = await db?.startConnectionLog(
        engine: profile.engine,
        profileId: profile.id,
      );
    } catch (e) {
      await db?.startConnectionLog(
        engine: profile.engine,
        profileId: profile.id,
      ).then((id) => db?.endConnectionLog(id, errorText: '$e'));
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _host.stop();
    await _finishLog();
  }

  Future<void> _finishLog() async {
    final id = _activeLogId;
    if (id == null) return;
    _activeLogId = null;
    final st = await _host.status();
    await db?.endConnectionLog(
      id,
      bytesUp: st.uploadBytes,
      bytesDown: st.downloadBytes,
      errorText: st.errorMessage,
    );
  }

  Stream<VpnStatus> watch() => _host.statusStream();

  Future<void> _waitFor(VpnState target,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final s = await _host.status();
      if (s.state == target) return;
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }
}

/// Выбирается в main() после probe нативного канала.
/// По умолчанию MockVpnHost — чтобы UI-скелет работал без нативных плагинов.
final vpnHostProvider = Provider<VpnHost>((ref) {
  throw UnimplementedError('vpnHostProvider must be overridden in main()');
});

final vpnSessionProvider = Provider<VpnSessionManager>((ref) {
  final preset = ref.watch(currentClientPresetProvider);
  final modeStr = ref.watch(connectionModeProvider);
  final mode = modeStr == ConnectionMode.proxy.name
      ? ConnectionMode.proxy
      : ConnectionMode.tun;
  return VpnSessionManager(
    ref.watch(vpnHostProvider),
    preset: preset,
    mode: mode,
    db: ref.watch(databaseProvider),
  );
});

final vpnStatusProvider = StreamProvider<VpnStatus>(
  (ref) => ref.watch(vpnSessionProvider).watch(),
);
