import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Bandeau d'étape numéroté — repère visuel fort « où je suis » (1, 2, 3…).
class StepHeader extends StatelessWidget {
  final int numero;
  final String titre;
  final String? sousTitre;
  const StepHeader(
      {super.key, required this.numero, required this.titre, this.sousTitre});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                color: AppColors.gold, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$numero',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge!
                    .copyWith(color: AppColors.ink, fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: Theme.of(context).textTheme.headlineSmall),
                if (sousTitre != null)
                  Text(sousTitre!,
                      style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      );
}

enum PillKind { ok, warn, danger, neutral }

/// Pastille de statut : couleur + icône + un mot. Lisible sans lire.
class StatusPill extends StatelessWidget {
  final PillKind kind;
  final String label;
  const StatusPill({super.key, required this.kind, required this.label});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (kind) {
      PillKind.ok => (AppColors.ok.withValues(alpha: 0.12), AppColors.ok, Icons.check_circle),
      PillKind.warn => (AppColors.warn.withValues(alpha: 0.14), AppColors.warn, Icons.error),
      PillKind.danger => (AppColors.danger.withValues(alpha: 0.12), AppColors.danger, Icons.block),
      PillKind.neutral => (AppColors.line, AppColors.inkSoft, Icons.schedule),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 6),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelLarge!
                .copyWith(color: fg, fontSize: 14)),
      ]),
    );
  }
}

/// Grande tuile d'action : icône colorée + titre + flèche. Cible tactile large.
class ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titre;
  final String? sousTitre;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  const ActionTile({
    super.key,
    required this.icon,
    required this.titre,
    this.sousTitre,
    this.color = AppColors.primary,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre,
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(fontSize: 18)),
                    if (sousTitre != null)
                      Text(sousTitre!,
                          style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              trailing ??
                  (onTap != null
                      ? const Icon(Icons.chevron_right,
                          color: AppColors.inkSoft)
                      : const SizedBox.shrink()),
            ]),
          ),
        ),
      );
}

enum AppMsgKind { info, success, warning, error }

/// Dialog modal simple et lisible (remplace les SnackBars) : grosse icône
/// colorée + message court + un seul bouton « OK ». Adapté faible niveau lecture.
Future<void> showAppMessage(BuildContext context, String message,
    {AppMsgKind kind = AppMsgKind.info, String? titre}) {
  final (color, icon, defautTitre) = switch (kind) {
    AppMsgKind.success => (AppColors.ok, Icons.check_circle, 'Réussi'),
    AppMsgKind.warning => (AppColors.warn, Icons.error, 'Attention'),
    AppMsgKind.error => (AppColors.danger, Icons.cancel, 'Erreur'),
    AppMsgKind.info => (AppColors.primary, Icons.info, 'Information'),
  };
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 42),
            ),
            const SizedBox(height: 16),
            Text(titre ?? defautTitre,
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message,
                style: Theme.of(ctx).textTheme.bodyLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            BigButton(
                icon: Icons.check,
                label: 'OK',
                color: color,
                onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    ),
  );
}

/// Bouton plein largeur avec grosse icône — action principale d'un écran.
class BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  const BigButton(
      {super.key,
      required this.icon,
      required this.label,
      this.onPressed,
      this.color});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        style: color == null
            ? null
            : FilledButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(64),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18))),
        icon: Icon(icon, size: 26),
        label: Text(label),
      );
}
