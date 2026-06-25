import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/ui/ui_kit.dart';
import '../domain/entities/score_result.dart';

/// Écran de résultat : score /100, éligibilité bonus, lecture immédiate couleur.
class ScoreResultScreen extends StatelessWidget {
  final ScoreResult resultat;
  final String chargementId;
  const ScoreResultScreen(
      {super.key, required this.resultat, required this.chargementId});

  @override
  Widget build(BuildContext context) {
    final bonus = resultat.eligible && resultat.score >= 80;
    final couleur = !resultat.eligible
        ? AppColors.danger
        : bonus
            ? AppColors.ok
            : AppColors.warn;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Résultat')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            // Jauge ronde simple
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: couleur.withValues(alpha: 0.12),
                  border: Border.all(color: couleur, width: 8)),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${resultat.score}',
                        style: t.displaySmall!
                            .copyWith(fontSize: 64, color: couleur)),
                    Text('sur 100', style: t.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            if (!resultat.eligible)
              const StatusPill(kind: PillKind.danger, label: 'Rejeté')
            else if (bonus)
              const StatusPill(kind: PillKind.ok, label: 'Bonus accordé')
            else
              const StatusPill(kind: PillKind.warn, label: 'Pas de bonus'),
            const SizedBox(height: 16),
            Text(
              !resultat.eligible
                  ? 'Un critère obligatoire manque'
                  : bonus
                      ? 'Score ≥ 80 : tu reçois le bonus'
                      : 'Score sous 80 : pas de bonus cette fois',
              style: t.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            BigButton(
              icon: Icons.home,
              label: 'Terminer',
              onPressed: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}
