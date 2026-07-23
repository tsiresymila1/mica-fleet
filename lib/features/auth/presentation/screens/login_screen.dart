import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _ctrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _loading = false;
  bool _pwdVisible = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus(); // libère l'écran pendant l'attente
    setState(() => _loading = true);
    final r = await ref
        .read(authControllerProvider.notifier)
        .login(_ctrl.text, _pwdCtrl.text);
    if (!mounted) return;
    await r.match(
      (f) async {
        setState(() => _loading = false);
        await showAppMessage(
          context,
          switch (f) {
            ValidationFailure(:final message) => message,
            AuthFailure(:final message) =>
              message ?? 'Identifiant ou mot de passe incorrect',
            NetworkFailure(:final message) =>
              message ?? 'Serveur injoignable',
            _ => 'Identifiant ou mot de passe incorrect',
          },
          kind: AppMsgKind.error,
          titre: 'Connexion impossible',
        );
      },
      (fournisseur) async => context.go('/home'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Pas d'AppBar ici : sans ça les icônes système restent claires (héritées
    // des écrans à AppBar verte) et disparaissent sur ce fond clair.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kOverlaySurClair,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // Marque
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.terrain,
                    color: AppColors.gold,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Mica', style: t.displaySmall),
                const SizedBox(height: 4),
                Text(
                  'Suivi du chargement à la mine',
                  style: t.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 1),
                // Saisie
                TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submit(),
                  style: t.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'Mon identifiant',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdCtrl,
                  obscureText: !_pwdVisible,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submit(),
                  style: t.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_pwdVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      tooltip: _pwdVisible ? 'Cacher' : 'Voir',
                      onPressed: () =>
                          setState(() => _pwdVisible = !_pwdVisible),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                BigButton(
                  icon: Icons.login,
                  label: _loading ? 'Connexion…' : 'Entrer',
                  onPressed: _loading ? null : _submit,
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
