import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/client_preset.dart';

class PingResult {
  PingResult({required this.host, required this.ms, required this.ok, this.error});
  final String host;
  final int ms;
  final bool ok;
  final String? error;
}

class SpeedResult {
  SpeedResult({required this.downloadKbps, required this.bytes, required this.elapsedMs});
  final double downloadKbps;
  final int bytes;
  final int elapsedMs;
}

/// Утилиты сетевых тестов: ping до адреса сервера, проверка URL, speed test,
/// получение публичного IP. Все запросы помечаются User-Agent текущего
/// [ClientPreset] (подмена клиента).
class NetworkService {
  NetworkService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

  Dio _withUa(ClientPreset preset, {Duration? timeout}) {
    _dio.options.headers['User-Agent'] = preset.userAgent;
    if (timeout != null) {
      _dio.options.receiveTimeout = timeout;
      _dio.options.sendTimeout = timeout;
      _dio.options.connectTimeout = timeout;
    }
    return _dio;
  }

  /// TCP connect-пинг. Самый дешёвый способ оценить доступность сервера.
  Future<PingResult> tcpPing(String host, int port,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      s.destroy();
      return PingResult(host: host, ms: sw.elapsedMilliseconds, ok: true);
    } catch (e) {
      sw.stop();
      return PingResult(
        host: host,
        ms: sw.elapsedMilliseconds,
        ok: false,
        error: '$e',
      );
    }
  }

  /// HTTP(S) URL-тест. Возвращает время до первого ответа.
  Future<PingResult> urlTest(String url, {required ClientPreset preset}) async {
    final sw = Stopwatch()..start();
    try {
      await _withUa(preset, timeout: const Duration(seconds: 5))
          .headUri<dynamic>(Uri.parse(url));
      sw.stop();
      return PingResult(host: url, ms: sw.elapsedMilliseconds, ok: true);
    } catch (e) {
      sw.stop();
      return PingResult(
          host: url, ms: sw.elapsedMilliseconds, ok: false, error: '$e');
    }
  }

  /// Простейший speed test: скачивает [bytes] байт и считает скорость.
  Future<SpeedResult> speedTest({
    String url = 'https://speed.cloudflare.com/__down?bytes=5000000',
    required ClientPreset preset,
  }) async {
    final sw = Stopwatch()..start();
    final resp = await _withUa(preset, timeout: const Duration(seconds: 20))
        .get<List<int>>(url,
            options: Options(responseType: ResponseType.bytes));
    sw.stop();
    final bytes = (resp.data ?? const []).length;
    final ms = sw.elapsedMilliseconds;
    final kbps = ms == 0 ? 0.0 : (bytes * 8 / 1000) / (ms / 1000);
    return SpeedResult(downloadKbps: kbps, bytes: bytes, elapsedMs: ms);
  }

  /// Публичный IP (через сторонний сервис). Клиент — тот же preset.
  Future<String?> publicIp({required ClientPreset preset}) async {
    try {
      final r = await _withUa(preset, timeout: const Duration(seconds: 5))
          .get<String>('https://api.ipify.org',
              options: Options(responseType: ResponseType.plain));
      return (r.data ?? '').trim();
    } catch (_) {
      return null;
    }
  }
}
