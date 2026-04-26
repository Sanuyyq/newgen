import 'engine_kind.dart';

enum SubscriptionSource { builtin, remoteBuiltin, url, manual, qr }

class Subscription {
  final int? id;
  final EngineKind engine;
  final String name;
  final SubscriptionSource source;
  final String? url;
  final String? rawPayload;
  final DateTime? lastUpdated;
  final bool autoUpdate;

  const Subscription({
    this.id,
    required this.engine,
    required this.name,
    required this.source,
    this.url,
    this.rawPayload,
    this.lastUpdated,
    this.autoUpdate = false,
  });
}
