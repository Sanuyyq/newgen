/// Тип VPN-движка. Значения стабильны — сохраняются в БД и передаются в нативный слой.
enum EngineKind {
  vless(0, 'VLESS'),
  awg(1, 'Amnezia WG');

  final int code;
  final String label;
  const EngineKind(this.code, this.label);

  static EngineKind fromCode(int c) =>
      EngineKind.values.firstWhere((e) => e.code == c);
}
