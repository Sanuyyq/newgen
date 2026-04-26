import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/engine_kind.dart';
import '../models/profile.dart';
import '../models/subscription.dart';

/// Лёгкая обёртка над sqflite. Без codegen, чтобы скелет собирался без build_runner.
class NegernDb {
  NegernDb._(this._db);
  final Database _db;

  static NegernDb? _instance;
  static NegernDb get instance {
    final i = _instance;
    if (i == null) throw StateError('NegernDb not initialized');
    return i;
  }

  static Future<NegernDb> initialize() async {
    if (_instance != null) return _instance!;

    // На десктопе используем FFI.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'negern.db');
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    final inst = NegernDb._(db);
    _instance = inst;
    await inst._seedIfEmpty();
    return inst;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE subscriptions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        engine INTEGER NOT NULL,
        name TEXT NOT NULL,
        source TEXT NOT NULL,
        url TEXT,
        raw_payload TEXT,
        last_updated INTEGER,
        auto_update INTEGER NOT NULL DEFAULT 0
      );
    ''');
    await db.execute('''
      CREATE TABLE profiles(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subscription_id INTEGER,
        engine INTEGER NOT NULL,
        name TEXT NOT NULL,
        remark TEXT,
        config_json TEXT NOT NULL,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        tags TEXT,
        latency_ms INTEGER,
        last_used_at INTEGER,
        FOREIGN KEY(subscription_id) REFERENCES subscriptions(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
    await db.execute(_connectionLogDdl);
  }

  static const _connectionLogDdl = '''
    CREATE TABLE connection_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      engine INTEGER NOT NULL,
      profile_id INTEGER,
      started_at INTEGER NOT NULL,
      ended_at INTEGER,
      bytes_up INTEGER NOT NULL DEFAULT 0,
      bytes_down INTEGER NOT NULL DEFAULT 0,
      error_text TEXT
    );
  ''';

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await db.execute(_connectionLogDdl);
    }
  }

  Future<void> _seedIfEmpty() async {
    final count = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM subscriptions')) ??
        0;
    if (count > 0) return;

    final raw = await rootBundle.loadString('assets/builtin_profiles.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    await _db.transaction((txn) async {
      Future<void> seed(EngineKind engine, String key) async {
        final subId = await txn.insert('subscriptions', {
          'engine': engine.code,
          'name': 'Builtin ${engine.label}',
          'source': SubscriptionSource.builtin.name,
          'url': null,
          'raw_payload': null,
          'last_updated': DateTime.now().millisecondsSinceEpoch,
          'auto_update': 0,
        });
        for (final item in (json[key] as List).cast<Map<String, dynamic>>()) {
          await txn.insert('profiles', {
            'subscription_id': subId,
            'engine': engine.code,
            'name': item['name'],
            'remark': item['remark'],
            'config_json': jsonEncode(item['config']),
            'is_builtin': 1,
            'tags': (item['tags'] as List?)?.cast<String>().join(','),
          });
        }
      }

      await seed(EngineKind.vless, 'vless');
      await seed(EngineKind.awg, 'awg');
    });
  }

  // ---------------- Settings ----------------
  Future<String?> getSetting(String key) async {
    final rows = await _db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ---------------- Subscriptions ----------------
  Future<List<Subscription>> listSubscriptions(EngineKind engine) async {
    final rows = await _db.query('subscriptions',
        where: 'engine = ?', whereArgs: [engine.code], orderBy: 'id ASC');
    return rows.map(_subFromRow).toList();
  }

  Future<int> insertSubscription(Subscription s) async {
    return _db.insert('subscriptions', {
      'engine': s.engine.code,
      'name': s.name,
      'source': s.source.name,
      'url': s.url,
      'raw_payload': s.rawPayload,
      'last_updated': s.lastUpdated?.millisecondsSinceEpoch,
      'auto_update': s.autoUpdate ? 1 : 0,
    });
  }

  Future<void> deleteSubscription(int id) async {
    await _db.delete('profiles', where: 'subscription_id = ?', whereArgs: [id]);
    await _db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> touchSubscription(int id,
      {DateTime? lastUpdated, String? rawPayload}) async {
    await _db.update(
      'subscriptions',
      {
        if (lastUpdated != null)
          'last_updated': lastUpdated.millisecondsSinceEpoch,
        if (rawPayload != null) 'raw_payload': rawPayload,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------- Profiles ----------------
  Future<List<VpnProfile>> listProfiles(EngineKind engine) async {
    final rows = await _db.query('profiles',
        where: 'engine = ?', whereArgs: [engine.code], orderBy: 'id ASC');
    return rows.map(_profileFromRow).toList();
  }

  Future<VpnProfile?> getProfile(int id) async {
    final rows =
        await _db.query('profiles', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _profileFromRow(rows.first);
  }

  Future<int> insertProfile(VpnProfile p) async {
    return _db.insert('profiles', {
      'subscription_id': p.subscriptionId,
      'engine': p.engine.code,
      'name': p.name,
      'remark': p.remark,
      'config_json': jsonEncode(p.config),
      'is_builtin': p.isBuiltin ? 1 : 0,
      'tags': p.tags.join(','),
      'latency_ms': p.latencyMs,
      'last_used_at': p.lastUsedAt?.millisecondsSinceEpoch,
    });
  }

  Future<void> deleteProfile(int id) async {
    await _db.delete('profiles', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateProfileLatency(int id, int? latencyMs) async {
    await _db.update(
      'profiles',
      {'latency_ms': latencyMs},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> replaceSubscriptionProfiles(
      int subscriptionId, List<VpnProfile> profiles) async {
    await _db.transaction((txn) async {
      await txn.delete('profiles',
          where: 'subscription_id = ?', whereArgs: [subscriptionId]);
      for (final p in profiles) {
        await txn.insert('profiles', {
          'subscription_id': subscriptionId,
          'engine': p.engine.code,
          'name': p.name,
          'remark': p.remark,
          'config_json': jsonEncode(p.config),
          'is_builtin': 0,
          'tags': p.tags.join(','),
        });
      }
    });
  }

  // ---------------- Connection log ----------------
  Future<int> startConnectionLog({
    required EngineKind engine,
    int? profileId,
  }) async {
    return _db.insert('connection_log', {
      'engine': engine.code,
      'profile_id': profileId,
      'started_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> endConnectionLog(
    int id, {
    int bytesUp = 0,
    int bytesDown = 0,
    String? errorText,
  }) async {
    await _db.update(
      'connection_log',
      {
        'ended_at': DateTime.now().millisecondsSinceEpoch,
        'bytes_up': bytesUp,
        'bytes_down': bytesDown,
        if (errorText != null) 'error_text': errorText,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> recentConnectionLog({int limit = 50}) {
    return _db.query('connection_log',
        orderBy: 'started_at DESC', limit: limit);
  }

  Subscription _subFromRow(Map<String, Object?> r) => Subscription(
        id: r['id'] as int,
        engine: EngineKind.fromCode(r['engine'] as int),
        name: r['name'] as String,
        source: SubscriptionSource.values.firstWhere(
          (e) => e.name == r['source'],
          orElse: () => SubscriptionSource.manual,
        ),
        url: r['url'] as String?,
        rawPayload: r['raw_payload'] as String?,
        lastUpdated: r['last_updated'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['last_updated'] as int),
        autoUpdate: (r['auto_update'] as int? ?? 0) == 1,
      );

  VpnProfile _profileFromRow(Map<String, Object?> r) => VpnProfile(
        id: r['id'] as int,
        subscriptionId: r['subscription_id'] as int?,
        engine: EngineKind.fromCode(r['engine'] as int),
        name: r['name'] as String,
        remark: r['remark'] as String?,
        config: (jsonDecode(r['config_json'] as String) as Map)
            .cast<String, dynamic>(),
        isBuiltin: (r['is_builtin'] as int? ?? 0) == 1,
        tags: ((r['tags'] as String?) ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        latencyMs: r['latency_ms'] as int?,
        lastUsedAt: r['last_used_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['last_used_at'] as int),
      );
}
