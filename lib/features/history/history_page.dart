import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/engine_kind.dart';
import '../../core/providers.dart';

/// История подключений (таблица connection_log).
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  late Future<List<Map<String, Object?>>> _future = _load();

  Future<List<Map<String, Object?>>> _load() {
    return ref.read(databaseProvider).recentConnectionLog(limit: 200);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История подключений'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _future,
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('Пока нет записей.'));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _HistoryTile(rows[i]),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.row);
  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final engineCode = row['engine'] as int;
    final engine = EngineKind.fromCode(engineCode);
    final startedAt = DateTime.fromMillisecondsSinceEpoch(
        row['started_at'] as int);
    final endedAtMs = row['ended_at'] as int?;
    final endedAt = endedAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(endedAtMs);
    final duration = endedAt == null
        ? 'идёт'
        : _fmtDuration(endedAt.difference(startedAt));
    final up = row['bytes_up'] as int? ?? 0;
    final down = row['bytes_down'] as int? ?? 0;
    final error = row['error_text'] as String?;
    final isError = error != null && error.isNotEmpty;

    return ListTile(
      leading: Icon(
        isError
            ? Icons.error_outline
            : (engine == EngineKind.vless ? Icons.shield : Icons.vpn_key),
        color: isError ? Colors.redAccent : Colors.tealAccent,
      ),
      title: Text('${engine.label} · $duration'),
      subtitle: Text(
        isError
            ? error
            : '${_fmtDateTime(startedAt)}  ·  ↑${_fmtBytes(up)}  ↓${_fmtBytes(down)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _fmtDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} с';
    if (d.inMinutes < 60) return '${d.inMinutes} мин';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '$h ч $m мин';
  }

  String _fmtDateTime(DateTime t) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b Б';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
  }
}
