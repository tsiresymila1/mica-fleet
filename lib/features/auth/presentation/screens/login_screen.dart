import 'package:flutter/material.dart';
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
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ref
        .read(authControllerProvider.notifier)
        .login(_ctrl.text, _pwdCtrl.text);
    r.match(
      (f) => setState(() {
        _error = f is ValidationFailure ? f.message : 'Identifiant ou mot de passe incorrect';
        _loading = false;
      }),
      (fournisseur) {
        if (mounted) context.go('/home');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      // appBar: AppBar(
      //   title: Text('Mica', style: t.displaySmall!.copyWith(fontSize: 40)),
      // ),
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
                obscureText: true,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _submit(),
                style: t.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                StatusPill(kind: PillKind.danger, label: _error!),
              ],
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
    );
  }
}
