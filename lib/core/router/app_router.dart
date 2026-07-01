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
import '../../features/scoring/domain/entities/score_result.dart';
import '../../features/scoring/presentation/score_result_screen.dart';
import '../../features/dev/dev_scenarios_screen.dart';

/// Données passées à l'écran de score via `extra`.
typedef ScoreArgs = ({ScoreResult resultat, String chargementId});

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
      GoRoute(
          path: '/chargement', builder: (_, _) => const ChargementScreen()),
      GoRoute(
          path: '/detail/:id',
          builder: (_, s) =>
              ChargementDetailScreen(chargementId: s.pathParameters['id']!)),
      GoRoute(
          path: '/suivi/:id',
          builder: (_, s) =>
              SuiviChargementScreen(chargementId: s.pathParameters['id']!)),
      GoRoute(
          path: '/transbordement/:id',
          builder: (_, s) =>
              TransbordementScreen(chargementId: s.pathParameters['id']!)),
      GoRoute(
          path: '/arrivee/:id',
          builder: (_, s) =>
              ArriveeScreen(chargementId: s.pathParameters['id']!)),
      GoRoute(
          path: '/score',
          builder: (_, s) {
            final args = s.extra as ScoreArgs;
            return ScoreResultScreen(
                resultat: args.resultat, chargementId: args.chargementId);
          }),
      GoRoute(
          path: '/dev-scenarios',
          builder: (_, _) => const DevScenariosScreen()),
    ],
  );
});
