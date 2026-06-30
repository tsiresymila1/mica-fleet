import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../providers/auth_provider.dart';
import '../../../loading/presentation/screens/home_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ref.read(loginProvider)(_ctrl.text);
    r.match(
      (f) => setState(() {
        _error = 'Identifiant inconnu';
        _loading = false;
      }),
      (fournisseur) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(fournisseurId: fournisseur.id),
          ),
        );
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
