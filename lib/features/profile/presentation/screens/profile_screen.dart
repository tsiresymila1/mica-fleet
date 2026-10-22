import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/error/failure.dart';
import '../../../../shared/ui/map_dialog.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../depot/presentation/providers/depot_provider.dart';
import '../../../loading/presentation/providers/chargements_list_provider.dart';
import '../../../mines/domain/entities/mine.dart';
import '../../../mines/domain/entities/mine_submission.dart';
import '../../../mines/presentation/providers/mine_submissions_provider.dart';
import '../../../mines/presentation/providers/mines_provider.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../../update/presentation/app_update_provider.dart';
import '../../../update/presentation/app_update_ui.dart';

/// Identité et actions du compte connecté.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fournisseur = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: ListView(
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
          const SizedBox(height: 8),
          ActionTile(
            icon: Icons.help_outline,
            color: AppColors.primary,
            titre: 'Aide',
            sousTitre: 'Guides et support',
            onTap: () => context.push('/aide'),
          ),
        ],
      ),
    );
  }
}

/// Référentiel des sites autorisés, avec recherche sur leurs informations visibles.
class SitesScreen extends ConsumerStatefulWidget {
  const SitesScreen({super.key});

  @override
  ConsumerState<SitesScreen> createState() => _SitesScreenState();
}

class _SitesScreenState extends ConsumerState<SitesScreen> {
  final _search = TextEditingController();
  int _tab = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openMineLots(Mine mine) async {
    final lotId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _MineLotsSheet(mine: mine),
    );
    if (lotId != null && mounted) await context.push('/detail/$lotId');
  }

  @override
  Widget build(BuildContext context) {
    final mines = ref.watch(minesProvider);
    final submissions = ref.watch(mineSubmissionsProvider);
    final depots = ref.watch(activeDepotsProvider);
    final query = _search.text.trim().toLowerCase();
    final mineItems =
        mines.asData?.value
            .where(
              (m) => [
                m.nom,
                m.id,
                m.reference,
                m.note,
                m.region,
                m.district,
                m.commune,
                m.fokontany,
                if (m.createdAt != null)
                  DateFormat('dd/MM/yyyy').format(m.createdAt!),
              ].whereType<String>().join(' ').toLowerCase().contains(query),
            )
            .toList() ??
        [];
    final localSubmissions =
        submissions.asData?.value
            .where(
              (submission) =>
                  submission.serverId == null &&
                  (submission.state == MineSubmissionState.localPending ||
                      submission.state ==
                          MineSubmissionState.awaitingAttachments ||
                      submission.state ==
                          MineSubmissionState.pendingValidation),
            )
            .toList() ??
        [];
    final localMines = localSubmissions
        .where(
          (submission) => [
            submission.nom,
            submission.payloadId,
            DateFormat('dd/MM/yyyy').format(submission.createdAt),
            'à synchroniser',
          ].join(' ').toLowerCase().contains(query),
        )
        .toList();
    final mineCount = mines.asData == null || submissions.asData == null
        ? null
        : mines.asData!.value.length + localSubmissions.length;
    final depotItems =
        depots.asData?.value
            .where((d) => '${d.nom} ${d.id}'.toLowerCase().contains(query))
            .toList() ??
        [];
    return Scaffold(
      appBar: AppBar(title: const Text('Mes mines et dépôts')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(triggerSyncProvider).sync(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
          children: [
            Text(
              'Mes sites',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 3),
            Text(
              'Origines et sites autorisés',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _siteMetric(
                  context,
                  Icons.terrain_outlined,
                  mineCount,
                  'Mines suivies',
                ),
                const SizedBox(width: 8),
                _siteMetric(
                  context,
                  Icons.warehouse_outlined,
                  depots.asData?.value.length,
                  'Dépôts renseignés',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _tabButton(0, 'Mines', mineCount),
                const SizedBox(width: 8),
                _tabButton(1, 'Dépôts', depots.asData?.value.length),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _tab == 0
                    ? 'Rechercher une mine, une région, une référence…'
                    : 'Rechercher un dépôt…',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            if (_tab == 0) ...[
              Text(
                '${mineItems.length + localMines.length} mine${mineItems.length + localMines.length > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              if (mines.isLoading || submissions.isLoading)
                const LinearProgressIndicator()
              else if (mines.hasError)
                const _Muted('Référentiel indisponible')
              else if (mineItems.isEmpty &&
                  localMines.isEmpty &&
                  !submissions.hasError)
                const _Muted('Aucune mine trouvée')
              else
                for (final m in mineItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _SiteCard(
                      id: m.id,
                      name: m.nom,
                      reference: m.reference,
                      note: m.note,
                      date: m.createdAt == null
                          ? null
                          : DateFormat('dd/MM/yyyy').format(m.createdAt!),
                      location: _mineLocation(m),
                      statusColor: AppColors.ok,
                      statusLabel: 'Synchronisée',
                      onTap: () => _openMineLots(m),
                    ),
                  ),
              for (final submission in localMines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _SiteCard(
                    id: 'local-${submission.payloadId}',
                    name: submission.nom,
                    reference: null,
                    date: DateFormat('dd/MM/yyyy').format(submission.createdAt),
                    statusColor: AppColors.warn,
                    statusLabel: 'À synchroniser',
                    onTap: () async {
                      await context.push('/mines-manual');
                      ref.invalidate(mineSubmissionsProvider);
                      ref.invalidate(minesProvider);
                    },
                  ),
                ),
              if (submissions.hasError)
                const _Muted('Propositions locales indisponibles'),
            ] else ...[
              Text(
                '${depotItems.length} dépôt${depotItems.length > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              if (depots.isLoading)
                const LinearProgressIndicator()
              else if (depots.hasError)
                const _Muted('Référentiel indisponible')
              else if (depotItems.isEmpty)
                const _Muted('Aucun dépôt trouvé')
              else
                for (final d in depotItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _SiteCard(
                      id: d.id,
                      name: d.nom,
                      reference: d.id,
                      onTap: () => showLocationMap(
                        context,
                        titre: d.nom,
                        lat: d.lat,
                        lon: d.lon,
                        rayonMetres: d.rayonMetres,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabButton(int value, String label, int? count) => Expanded(
    child: OutlinedButton(
      onPressed: () => setState(() {
        _tab = value;
        _search.clear();
      }),
      style: OutlinedButton.styleFrom(
        backgroundColor: _tab == value ? AppColors.primary : Colors.white,
        foregroundColor: _tab == value ? Colors.white : AppColors.inkSoft,
        side: BorderSide(
          color: _tab == value ? AppColors.primary : AppColors.line,
        ),
      ),
      child: Text('$label${count == null ? '' : ' ($count)'}'),
    ),
  );

  Widget _siteMetric(
    BuildContext context,
    IconData icon,
    int? count,
    String label,
  ) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 25),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${count ?? '—'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  String _mineLocation(Mine mine) {
    final parts = [
      mine.region,
      mine.district,
      mine.commune,
      mine.fokontany,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({
    required this.id,
    required this.name,
    required this.reference,
    required this.onTap,
    this.date,
    this.location,
    this.note,
    this.statusColor,
    this.statusLabel,
  });

  final String id;
  final String name;
  final String? reference;
  final String? date;
  final String? location;
  final String? note;
  final Color? statusColor;
  final String? statusLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    key: ValueKey('site-$id'),
    color: AppColors.surface,
    elevation: 1,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          if (statusColor != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                key: ValueKey('site-status-$id'),
                width: 5,
                color: statusColor,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              statusColor == null ? 14 : 18,
              12,
              12,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (date != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        date!,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.inkSoft,
                    ),
                  ],
                ),
                if (statusLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    statusLabel!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _fact(
                  context,
                  'RÉFÉRENCE',
                  reference?.trim().isNotEmpty == true
                      ? reference!.trim()
                      : '—',
                ),
                if (location != null) ...[
                  const SizedBox(height: 9),
                  _fact(context, 'LOCALISATION', location!),
                ],
                if (note?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 9),
                  _fact(context, 'NOTE', note!.trim()),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fact(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9,
          letterSpacing: 0.7,
          color: AppColors.inkSoft,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
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

class _AppUpdateTile extends ConsumerWidget {
  const _AppUpdateTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final update = state.update;
    final busy = state.checking || state.downloading;
    return ActionTile(
      icon: Icons.system_update_alt,
      color: update?.mandatory == true ? AppColors.danger : AppColors.secondary,
      titre: busy
          ? 'Mise à jour en cours…'
          : update == null
          ? 'Mettre à jour l’application'
          : 'Version ${update.version} disponible',
      sousTitre: state.checking
          ? 'Vérification de la version…'
          : state.downloading
          ? 'Téléchargement en cours…'
          : update == null
          ? 'Vérifier et installer une nouvelle version'
          : update.mandatory
          ? 'Mise à jour obligatoire'
          : 'Appuyer pour télécharger',
      trailing: busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: busy ? null : () => checkAndOpenAppUpdate(context, ref),
    );
  }
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
            backgroundColor: AppColors.secondary,
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

class _Muted extends StatelessWidget {
  final String texte;
  const _Muted(this.texte);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(texte, style: Theme.of(context).textTheme.bodyMedium),
  );
}
