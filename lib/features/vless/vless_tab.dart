import 'package:flutter/material.dart';

import '../../core/models/engine_kind.dart';
import '../common/engine_tab.dart';

class VlessTab extends StatelessWidget {
  const VlessTab({super.key});

  @override
  Widget build(BuildContext context) =>
      const EngineTab(engine: EngineKind.vless);
}
