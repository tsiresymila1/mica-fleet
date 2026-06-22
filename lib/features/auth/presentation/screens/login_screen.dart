import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../../../loading/presentation/screens/chargement_screen.dart';

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
        _error = 'Échec connexion';
        _loading = false;
      }),
      (fournisseur) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => ChargementScreen(fournisseurId: fournisseur.id)));
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Connexion fournisseur')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                      labelText: 'Identifiant fournisseur',
                      border: OutlineInputBorder())),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: Text(_loading ? '...' : 'Se connecter')),
            ],
          ),
        ),
      );
}
