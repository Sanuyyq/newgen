import 'package:flutter/material.dart';

import '../../core/models/engine_kind.dart';
import '../common/engine_tab.dart';

class AwgTab extends StatelessWidget {
  const AwgTab({super.key});

  @override
  Widget build(BuildContext context) =>
      const EngineTab(engine: EngineKind.awg);
}
