import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Встроенный SOCKS5-сервер (RFC 1928) для раздачи интернета через VPN по LAN.
///
/// Важно: трафик заворачивается в VPN только тогда, когда VPN реально активен
/// и его TUN-интерфейс — default route. Без этого будет direct.
/// Это не хотспот: Wi-Fi SoftAP из Flutter-клиента сделать нельзя без
/// системных API.
///
/// Аутентификация:
///   - AuthMode.none — без пароля (удобно в доверенной LAN);
///   - AuthMode.userPass — RFC 1929 (usernameUsername/Password), аналог WPA2-Personal
///     на уровне прокси.
enum LanProxyAuth { none, userPass }

class LanProxyConfig {
  LanProxyConfig({
    this.bind = '0.0.0.0',
    this.port = 1080,
    this.auth = LanProxyAuth.none,
    this.user,
    this.pass,
  });
  final String bind;
  final int port;
  final LanProxyAuth auth;
  final String? user;
  final String? pass;
}

class LanProxyService {
  ServerSocket? _server;
  LanProxyConfig? _current;
  final _clients = <Socket>{};

  bool get isRunning => _server != null;
  LanProxyConfig? get current => _current;

  Future<void> start(LanProxyConfig cfg) async {
    await stop();
    final server = await ServerSocket.bind(cfg.bind, cfg.port, shared: true);
    _server = server;
    _current = cfg;
    server.listen(
      (client) => _handleClient(client, cfg),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _current = null;
    for (final c in _clients.toList()) {
      c.destroy();
    }
    _clients.clear();
  }

  Future<void> _handleClient(Socket client, LanProxyConfig cfg) async {
    _clients.add(client);
    final buf = _StreamBuffer(client);
    try {
      // 1. Greeting
      final head = await buf.readN(2);
      if (head[0] != 0x05) return;
      final nMethods = head[1];
      final methods = await buf.readN(nMethods);

      int chosen;
      if (cfg.auth == LanProxyAuth.none && methods.contains(0x00)) {
        chosen = 0x00;
      } else if (cfg.auth == LanProxyAuth.userPass && methods.contains(0x02)) {
        chosen = 0x02;
      } else {
        client.add([0x05, 0xFF]);
        await client.flush();
        return;
      }
      client.add([0x05, chosen]);
      await client.flush();

      // 2. Auth sub-negotiation (RFC 1929) если нужно.
      if (chosen == 0x02) {
        final ver = await buf.readN(1);
        if (ver[0] != 0x01) return;
        final ulen = (await buf.readN(1))[0];
        final user = String.fromCharCodes(await buf.readN(ulen));
        final plen = (await buf.readN(1))[0];
        final pass = String.fromCharCodes(await buf.readN(plen));
        final ok = user == (cfg.user ?? '') && pass == (cfg.pass ?? '');
        client.add([0x01, ok ? 0x00 : 0x01]);
        await client.flush();
        if (!ok) return;
      }

      // 3. Request
      final req = await buf.readN(4);
      if (req[0] != 0x05 || req[1] != 0x01) {
        // Only CONNECT supported.
        client.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await client.flush();
        return;
      }
      final atyp = req[3];
      String host;
      if (atyp == 0x01) {
        final ip = await buf.readN(4);
        host = '${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}';
      } else if (atyp == 0x03) {
        final len = (await buf.readN(1))[0];
        host = String.fromCharCodes(await buf.readN(len));
      } else if (atyp == 0x04) {
        final ip = await buf.readN(16);
        host = _formatIpv6(ip);
      } else {
        client.add([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await client.flush();
        return;
      }
      final portBytes = await buf.readN(2);
      final port = (portBytes[0] << 8) | portBytes[1];

      Socket? upstream;
      try {
        upstream = await Socket.connect(host, port,
            timeout: const Duration(seconds: 10));
      } catch (_) {
        client.add([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await client.flush();
        return;
      }

      client.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await client.flush();

      // Прокидываем остаток буфера + дальше трафик в обе стороны.
      if (buf.pending.isNotEmpty) upstream.add(buf.pending);
      final done = <Future<void>>[
        client.cast<List<int>>().pipe(upstream),
        upstream.cast<List<int>>().pipe(client),
      ];
      await Future.any(done).catchError((_) {});
    } catch (_) {
      // swallow
    } finally {
      _clients.remove(client);
      client.destroy();
    }
  }

  String _formatIpv6(Uint8List b) {
    final parts = <String>[];
    for (var i = 0; i < 16; i += 2) {
      parts.add(((b[i] << 8) | b[i + 1]).toRadixString(16));
    }
    return parts.join(':');
  }
}

/// Вспомогательный буфер поверх Socket: позволяет читать точно N байт.
class _StreamBuffer {
  _StreamBuffer(Socket s) {
    _sub = s.listen((chunk) {
      _buffer.addAll(chunk);
      _flushWaiters();
    }, onDone: _finish, onError: (_) => _finish(), cancelOnError: true);
  }

  late final StreamSubscription<Uint8List> _sub;
  final List<int> _buffer = [];
  final List<_Waiter> _waiters = [];
  bool _closed = false;

  Uint8List get pending => Uint8List.fromList(_buffer);

  Future<Uint8List> readN(int n) {
    final w = _Waiter(n);
    _waiters.add(w);
    _flushWaiters();
    return w.completer.future;
  }

  void _flushWaiters() {
    while (_waiters.isNotEmpty && _buffer.length >= _waiters.first.n) {
      final w = _waiters.removeAt(0);
      final bytes = Uint8List.fromList(_buffer.sublist(0, w.n));
      _buffer.removeRange(0, w.n);
      w.completer.complete(bytes);
    }
    if (_closed) {
      for (final w in _waiters) {
        w.completer.completeError(const SocketException('closed'));
      }
      _waiters.clear();
    }
  }

  void _finish() {
    _closed = true;
    _flushWaiters();
    _sub.cancel();
  }
}

class _Waiter {
  _Waiter(this.n);
  final int n;
  final Completer<Uint8List> completer = Completer<Uint8List>();
}
