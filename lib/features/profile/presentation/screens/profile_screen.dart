import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/network/api_error_details.dart';
import '../../../../core/error/failure.dart';
import '../../../../shared/ui/map_dialog.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../depot/presentation/providers/depot_provider.dart';
import '../../../loading/presentation/providers/chargements_list_provider.dart';
import '../../../mines/domain/entities/mine.dart';
import '../../../mines/presentation/providers/mines_provider.dart';
import '../../../mines/presentation/widgets/mine_overview_tile.dart';
import '../../../sync/presentation/sync_provider.dart';

/// Profil du fournisseur connecté : ses mines et ses dépôts autorisés
/// (référentiel synchronisé depuis Odoo). Lecture seule.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _openMineLots(BuildContext context, Mine mine) async {
    final lotId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _MineLotsSheet(mine: mine),
    );
    if (lotId != null && context.mounted) {
      await context.push('/detail/$lotId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fournisseur = ref.watch(authControllerProvider);
    final mines = ref.watch(minesProvider);
    final depots = ref.watch(activeDepotsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(triggerSyncProvider).sync(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            _Identite(
              nom: fournisseur?.nom ?? 'Fournisseur',
              id: fournisseur?.id ?? '',
            ),
            const SizedBox(height: 12),
            const _ChangePasswordTile(),
            const SizedBox(height: 8),
            const _AppUpdateTile(),
            const SizedBox(height: 24),
            StepHeader(
              numero: 1,
              titre: 'Mes mines',
              sousTitre: 'Lieux de chargement',
            ),
            const SizedBox(height: 8),
            mines.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const _Muted('Référentiel indisponible'),
              data: (list) => list.isEmpty
                  ? const _Muted('Aucune mine')
                  : Column(
                      children: list
                          .map(
                            (m) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: MineOverviewTile(
                                name: m.nom,
                                reference: m.reference,
                                note: m.note,
                                createdAt: m.createdAt,
                                onTap: () => _openMineLots(context, m),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 24),
            StepHeader(
              numero: 2,
              titre: 'Mes dépôts',
              sousTitre: 'Lieux de livraison',
            ),
            const SizedBox(height: 8),
            depots.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const _Muted('Référentiel indisponible'),
              data: (list) => list.isEmpty
                  ? const _Muted('Aucun dépôt')
                  : Column(
                      children: list
                          .map(
                            (d) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ActionTile(
                                icon: Icons.warehouse,
                                color: AppColors.primary,
                                titre: d.nom,
                                trailing: _Coord(lat: d.lat, lon: d.lon),
                                onTap: () => showLocationMap(
                                  context,
                                  titre: d.nom,
                                  lat: d.lat,
                                  lon: d.lon,
                                  rayonMetres: d.rayonMetres,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MineLotsSheet extends ConsumerWidget {
  const _MineLotsSheet({required this.mine});

  final Mine mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lots = ref.watch(lotsForMineProvider(mine.id));
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lots rattachés à ${mine.nom}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: lots.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    const Center(child: Text('Impossible de charger les lots')),
                data: (items) => items.isEmpty
                    ? const Center(
                        child: Text('Aucun lot rattaché à cette mine'),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final lot = items[index];
                          return ActionTile(
                            icon: Icons.inventory_2_outlined,
                            color: AppColors.primary,
                            titre: lot.serverReference ?? lot.id,
                            sousTitre: [
                              'Créé le ${dateFormat.format(lot.date)}',
                              [
                                if (lot.couleur?.trim().isNotEmpty == true)
                                  lot.couleur!.trim(),
                                if (lot.tonnage != null) '${lot.tonnage} kg',
                              ].join(' • '),
                              'Validation : ${_validationLabel(lot.validationStatus)}',
                              if (lot.score != null) 'Score : ${lot.score}/100',
                            ].where((line) => line.isNotEmpty).join('\n'),
                            onTap: () => Navigator.of(context).pop(lot.id),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _validationLabel(String status) => switch (status) {
    'validated' => 'Validé',
    'rejected' => 'Rejeté',
    _ => 'En attente',
  };
}

class _ChangePasswordTile extends ConsumerStatefulWidget {
  const _ChangePasswordTile();

  @override
  ConsumerState<_ChangePasswordTile> createState() =>
      _ChangePasswordTileState();
}

class _AppUpdateTile extends ConsumerStatefulWidget {
  const _AppUpdateTile();

  @override
  ConsumerState<_AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends ConsumerState<_AppUpdateTile> {
  bool _busy = false;
  double? _progress;

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final service = ref.read(appUpdateServiceProvider);
      final check = await service.check();
      final update = check.update;
      if (!mounted) return;
      if (update == null) {
        await showAppMessage(
          context,
          'La version ${check.currentVersion} (${check.currentBuild}) est à jour.',
          kind: AppMsgKind.success,
        );
        return;
      }
      final accepted = await showConfirm(
        context,
        [
          'Version ${update.version} (${update.build}) disponible.',
          if (update.releaseNotes?.trim().isNotEmpty == true)
            update.releaseNotes!.trim(),
          'L’installation sera confirmée dans l’écran sécurisé d’Android.',
        ].join('\n\n'),
        titre: update.mandatory ? 'Mise à jour requise' : 'Nouvelle version',
        confirmLabel: 'Télécharger',
      );
      if (!accepted || !mounted) return;
      final status = await service.downloadAndInstall(
        update,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      if (status == 'permission_required') {
        await showAppMessage(
          context,
          'Autorise MICA Fleet à installer cette mise à jour, puis appuie de nouveau sur le bouton.',
          kind: AppMsgKind.warning,
        );
      } else {
        showAppToast(context, 'Installateur Android ouvert');
      }
    } catch (error) {
      if (mounted) {
        await showAppMessage(
          context,
          apiErrorDetails(error),
          kind: AppMsgKind.error,
          titre: 'Mise à jour impossible',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ActionTile(
        icon: Icons.system_update_alt,
        color: AppColors.gold,
        titre: _busy ? 'Mise à jour en cours…' : 'Mettre à jour l’application',
        sousTitre: _progress == null
            ? 'Vérifier et installer une nouvelle version'
            : 'Téléchargement ${(_progress! * 100).round()} %',
        onTap: _busy ? null : _update,
      ),
      if (_progress != null) LinearProgressIndicator(value: _progress),
    ],
  );
}

class _ChangePasswordTileState extends ConsumerState<_ChangePasswordTile> {
  bool _saving = false;

  Future<void> _open() async {
    final data = await showModalBottomSheet<_PasswordChangeData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PasswordChangeSheet(),
    );

    if (data == null || !mounted) return;
    if (data.newPassword != data.confirmation) {
      await showAppMessage(
        context,
        'La confirmation ne correspond pas au nouveau mot de passe.',
        kind: AppMsgKind.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await ref.read(changePasswordProvider)(
        currentPassword: data.currentPassword,
        newPassword: data.newPassword,
      );
      if (!mounted) return;
      await result.match(
        (failure) => showAppMessage(
          context,
          _failureMessage(failure),
          kind: AppMsgKind.error,
        ),
        (queued) => showAppMessage(
          context,
          queued
              ? 'Mot de passe modifié hors ligne. Il sera synchronisé automatiquement.'
              : 'Mot de passe modifié.',
          kind: AppMsgKind.success,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ActionTile(
    icon: Icons.password,
    color: AppColors.primary,
    titre: _saving ? 'Modification…' : 'Modifier le mot de passe',
    sousTitre: 'Disponible aussi hors ligne',
    onTap: _saving ? null : _open,
  );
}

class _PasswordChangeData {
  const _PasswordChangeData({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmation,
  });

  final String currentPassword;
  final String newPassword;
  final String confirmation;
}

class _PasswordChangeSheet extends ConsumerStatefulWidget {
  const _PasswordChangeSheet();

  @override
  ConsumerState<_PasswordChangeSheet> createState() =>
      _PasswordChangeSheetState();
}

class _PasswordChangeSheetState extends ConsumerState<_PasswordChangeSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();
  bool _currentHidden = true;
  bool _nextHidden = true;
  bool _confirmationHidden = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _PasswordChangeData(
        currentPassword: _current.text,
        newPassword: _next.text,
        confirmation: _confirmation.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Spacer(),
                Text(
                  'Modifier le mot de passe',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Annuler',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          TextField(
            controller: _current,
            obscureText: _currentHidden,
            decoration: InputDecoration(
              labelText: 'Mot de passe actuel',
              suffixIcon: IconButton(
                icon: Icon(
                  _currentHidden ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _currentHidden = !_currentHidden),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _next,
            obscureText: _nextHidden,
            decoration: InputDecoration(
              labelText: 'Nouveau mot de passe',
              helperText: '8 caractères minimum',
              suffixIcon: IconButton(
                icon: Icon(
                  _nextHidden ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _nextHidden = !_nextHidden),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirmation,
            obscureText: _confirmationHidden,
            decoration: InputDecoration(
              labelText: 'Confirmation',
              suffixIcon: IconButton(
                icon: Icon(
                  _confirmationHidden ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _confirmationHidden = !_confirmationHidden),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _failureMessage(Failure failure) => switch (failure) {
  NetworkFailure(:final message) => message ?? 'Connexion indisponible',
  DatabaseFailure(:final message) => message ?? 'Erreur locale',
  AuthFailure(:final message) => message ?? 'Mot de passe incorrect',
  ValidationFailure(:final message) => message,
  MockLocationFailure() => 'Erreur de position',
  UnexpectedFailure(:final message) => message ?? 'Erreur inattendue',
};

class _Identite extends StatelessWidget {
  final String nom;
  final String id;
  const _Identite({required this.nom, required this.id});

  @override
  Widget build(BuildContext context) {
    final initiale = nom.trim().isEmpty ? '?' : nom.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.gold,
            child: Text(
              initiale,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall!.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nom,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge!.copyWith(color: Colors.white),
                ),
                Text('ID : $id', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// GPS compact à droite d'une tuile.
class _Coord extends StatelessWidget {
  final double lat;
  final double lon;
  const _Coord({required this.lat, required this.lon});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.place, size: 16, color: AppColors.inkSoft),
      Text(
        '${lat.toStringAsFixed(3)}\n${lon.toStringAsFixed(3)}',
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  );
}

class _Muted extends StatelessWidget {
  final String texte;
  const _Muted(this.texte);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(texte, style: Theme.of(context).textTheme.bodyMedium),
  );
}
