import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/loading/presentation/screens/home_screen.dart';
import '../../features/loading/presentation/screens/chargement_screen.dart';
import '../../features/loading/presentation/screens/chargement_detail_screen.dart';
import '../../features/loading/presentation/screens/suivi_chargement_screen.dart';
import '../../features/transport/presentation/screens/transbordement_screen.dart';
import '../../features/depot/presentation/screens/arrivee_screen.dart';
import '../../features/dev/dev_scenarios_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Rafraîchit le routeur quand l'état d'auth change (login/logout).
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final connecte = ref.read(authControllerProvider) != null;
      final surLogin = state.matchedLocation == '/login';
      if (!connecte) return surLogin ? null : '/login';
      if (surLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/profil', builder: (_, _) => const ProfileScreen()),
      GoRoute(
          path: '/chargement', builder: (_, _) => const ChargementScreen()),
      // Détail = UN LOT (unité de traçabilité).
      GoRoute(
          path: '/detail/:lotId',
          builder: (_, s) =>
              ChargementDetailScreen(lotId: s.pathParameters['lotId']!)),
      // Récap juste après création : liste les lots créés (niveau SESSION).
      GoRoute(
          path: '/suivi/:sessionId',
          builder: (_, s) =>
              SuiviChargementScreen(sessionId: s.pathParameters['sessionId']!)),
      // Transport et arrivée = au niveau LOT : chaque lot suit son propre camion.
      GoRoute(
          path: '/transbordement/:lotId',
          builder: (_, s) => TransbordementScreen(
                lotId: s.pathParameters['lotId']!,
                ordre: int.tryParse(s.uri.queryParameters['ordre'] ?? ''),
              )),
      GoRoute(
          path: '/arrivee/:lotId',
          builder: (_, s) => ArriveeScreen(lotId: s.pathParameters['lotId']!)),
      GoRoute(
          path: '/dev-scenarios',
          builder: (_, _) => const DevScenariosScreen()),
    ],
  );
});
