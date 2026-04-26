import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../awg/awg_tab.dart';
import '../common/ip_badge.dart';
import '../vless/vless_tab.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaper = ref.watch(wallpaperPathProvider);

    return DefaultTabController(
      length: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (wallpaper != null && File(wallpaper).existsSync())
            Image.file(File(wallpaper), fit: BoxFit.cover)
          else
            const SizedBox.shrink(),
          if (wallpaper != null) Container(color: Colors.black.withOpacity(0.55)),
          Scaffold(
            backgroundColor:
                wallpaper != null ? Colors.transparent : null,
            appBar: AppBar(
              backgroundColor: wallpaper != null
                  ? Colors.black.withOpacity(0.35)
                  : null,
              title: const Text('Negern VPN'),
              actions: [
                const IpBadge(),
                IconButton(
                  tooltip: 'История',
                  icon: const Icon(Icons.history),
                  onPressed: () => context.push('/history'),
                ),
                IconButton(
                  tooltip: 'Настройки',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push('/settings'),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'VLESS', icon: Icon(Icons.shield_outlined)),
                  Tab(text: 'Amnezia WG', icon: Icon(Icons.lock_outline)),
                ],
              ),
            ),
            body: const TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                VlessTab(),
                AwgTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

