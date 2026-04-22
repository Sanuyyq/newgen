import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/models/engine_kind.dart';
import 'features/home/home_page.dart';
import 'features/profiles/add_profile_page.dart';
import 'features/profiles/profiles_page.dart';
import 'features/settings/settings_page.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(
      path: '/profiles/:kind',
      builder: (_, state) {
        final kind = _parseKind(state.pathParameters['kind']);
        return ProfilesPage(engine: kind);
      },
    ),
    GoRoute(
      path: '/profiles/:kind/add',
      builder: (_, state) {
        final kind = _parseKind(state.pathParameters['kind']);
        return AddProfilePage(engine: kind);
      },
    ),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
  ],
);

EngineKind _parseKind(String? s) =>
    s == 'awg' ? EngineKind.awg : EngineKind.vless;

class NegernApp extends StatelessWidget {
  const NegernApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Negern VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6EE7B7),
          brightness: Brightness.dark,
          surface: const Color(0xFF0B1020),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1020),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          color: const Color(0xFF121832),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF0F1530),
        ),
        tabBarTheme: const TabBarTheme(
          labelStyle: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      routerConfig: _router,
    );
  }
}
