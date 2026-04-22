import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/engine_kind.dart';
import '../../core/providers.dart';

class AddProfilePage extends ConsumerStatefulWidget {
  const AddProfilePage({super.key, required this.engine});

  final EngineKind engine;

  @override
  ConsumerState<AddProfilePage> createState() => _AddProfilePageState();
}

class _AddProfilePageState extends ConsumerState<AddProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tc;
  final _urlCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tc.dispose();
    _urlCtrl.dispose();
    _textCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Добавить ${widget.engine.label}'),
        bottom: TabBar(
          controller: _tc,
          tabs: const [
            Tab(text: 'URL'),
            Tab(text: 'Текст'),
            Tab(text: 'QR'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tc,
            children: [
              _urlTab(),
              _textTab(),
              _qrTab(),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _urlTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Имя подписки (необязательно)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _urlCtrl,
          decoration: const InputDecoration(
            labelText: 'URL подписки (base64 или список)',
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _runImport(_importUrl),
          icon: const Icon(Icons.cloud_download_outlined),
          label: const Text('Импортировать'),
        ),
      ],
    );
  }

  Widget _textTab() {
    final hint = widget.engine == EngineKind.vless
        ? 'vless://uuid@host:port?...'
        : '[Interface]\nPrivateKey = ...\n[Peer]\n...';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Имя профиля (необязательно)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _textCtrl,
          minLines: 6,
          maxLines: 20,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Конфиг',
            hintText: hint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _runImport(_importText),
          icon: const Icon(Icons.add),
          label: const Text('Добавить'),
        ),
      ],
    );
  }

  Widget _qrTab() {
    // mobile_scanner не поддерживается на Windows — показываем плейсхолдер.
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Сканирование QR доступно только на Android/iOS.\n'
            'На Windows используйте вкладку Текст или URL.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return MobileScanner(
      onDetect: (capture) {
        final code = capture.barcodes
            .map((b) => b.rawValue)
            .whereType<String>()
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        if (code.isEmpty || _busy) return;
        _textCtrl.text = code;
        _runImport(_importQr);
      },
    );
  }

  Future<void> _runImport(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      bumpRefresh(ref);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importUrl() async {
    final svc = ref.read(subscriptionServiceProvider);
    await svc.importUrl(
      engine: widget.engine,
      url: _urlCtrl.text.trim(),
      nameOverride: _trimOrNull(_nameCtrl.text),
    );
  }

  Future<void> _importText() async {
    final svc = ref.read(subscriptionServiceProvider);
    await svc.importManual(
      engine: widget.engine,
      text: _textCtrl.text,
      nameOverride: _trimOrNull(_nameCtrl.text),
    );
  }

  Future<void> _importQr() async {
    final svc = ref.read(subscriptionServiceProvider);
    await svc.importFromQr(
      engine: widget.engine,
      payload: _textCtrl.text,
      nameOverride: _trimOrNull(_nameCtrl.text),
    );
  }

  String? _trimOrNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }
}
