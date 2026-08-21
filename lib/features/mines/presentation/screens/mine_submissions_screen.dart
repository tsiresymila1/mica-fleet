import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/photo_view.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../sync/presentation/sync_provider.dart';
import '../../../sync/presentation/widgets/sync_icon_button.dart';
import '../../domain/entities/mine_submission.dart';
import '../providers/mine_submissions_provider.dart';
import '../providers/mines_provider.dart';
import '../widgets/mine_overview_tile.dart';

class MineSubmissionsScreen extends ConsumerWidget {
  const MineSubmissionsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(triggerSyncProvider).sync();
    ref.invalidate(mineSubmissionsProvider);
    ref.invalidate(minesProvider);
  }

  Future<void> _openDetails(
    BuildContext context,
    WidgetRef ref,
    MineSubmission submission,
  ) async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SubmissionDetailsSheet(submission: submission),
    );
    if (deleted == true) ref.invalidate(mineSubmissionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissions = ref.watch(mineSubmissionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mines proposées'),
        actions: [
          SyncIconButton(
            onPressed: () async {
              showAppToast(context, 'Synchronisation lancée');
              await _refresh(ref);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: submissions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('Impossible de charger : $error')),
            ],
          ),
          data: (items) => items.isEmpty
              ? const _EmptySubmissions()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _SubmissionTile(
                    items[index],
                    onTap: () => _openDetails(context, ref, items[index]),
                  ),
                ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
          icon: Icons.add_location_alt_outlined,
          label: 'Proposer une mine',
          onPressed: () async {
            final created = await context.push<bool>('/mines-manual/new');
            if (created == true) ref.invalidate(mineSubmissionsProvider);
          },
        ),
      ),
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  final MineSubmission submission;
  final VoidCallback onTap;
  const _SubmissionTile(this.submission, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uploaded = submission.photos.where((p) => p.uploaded).length;
    final status = _submissionStatus(submission.state);
    return MineOverviewTile(
      name: submission.nom,
      reference: null,
      note: null,
      createdAt: submission.createdAt,
      icon: status.icon,
      color: status.color,
      details: [
        '${submission.photos.length} positions',
        if (submission.state == MineSubmissionState.awaitingAttachments)
          'Photos $uploaded/${submission.photos.length}',
        if (submission.rejectionReason != null) submission.rejectionReason!,
      ],
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(kind: status.kind, label: status.label),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.inkSoft),
        ],
      ),
    );
  }
}

({String label, PillKind kind, Color color, IconData icon}) _submissionStatus(
  MineSubmissionState state,
) => switch (state) {
  MineSubmissionState.localPending => (
    label: 'À envoyer',
    kind: PillKind.warn,
    color: AppColors.warn,
    icon: Icons.cloud_upload_outlined,
  ),
  MineSubmissionState.awaitingAttachments => (
    label: 'Envoyée',
    kind: PillKind.neutral,
    color: AppColors.primary,
    icon: Icons.cloud_done_outlined,
  ),
  MineSubmissionState.pendingValidation => (
    label: 'Envoyée',
    kind: PillKind.neutral,
    color: AppColors.primary,
    icon: Icons.cloud_done_outlined,
  ),
  MineSubmissionState.approved => (
    label: 'Validée',
    kind: PillKind.ok,
    color: AppColors.ok,
    icon: Icons.verified_outlined,
  ),
  MineSubmissionState.rejected => (
    label: 'Refusée',
    kind: PillKind.danger,
    color: AppColors.danger,
    icon: Icons.block_outlined,
  ),
  MineSubmissionState.hidden => (
    label: 'Masquée',
    kind: PillKind.neutral,
    color: AppColors.inkSoft,
    icon: Icons.visibility_off_outlined,
  ),
};

class _SubmissionDetailsSheet extends ConsumerStatefulWidget {
  final MineSubmission submission;

  const _SubmissionDetailsSheet({required this.submission});

  @override
  ConsumerState<_SubmissionDetailsSheet> createState() =>
      _SubmissionDetailsSheetState();
}

class _SubmissionDetailsSheetState
    extends ConsumerState<_SubmissionDetailsSheet> {
  bool _deleting = false;
  bool _sending = false;

  Future<void> _sendNow() async {
    setState(() => _sending = true);
    final result = await ref
        .read(mineSubmissionActionsProvider)
        .sendNow(widget.submission.payloadId);
    if (!mounted) return;
    if (result.success) {
      await showAppMessage(
        context,
        'Mine et photos envoyées. La proposition reste en attente de '
        'validation du serveur.',
        kind: AppMsgKind.success,
      );
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    await showAppMessage(
      context,
      result.error ?? 'Impossible d’envoyer la proposition.',
      kind: AppMsgKind.error,
    );
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _delete() async {
    final sent = widget.submission.state != MineSubmissionState.localPending;
    final confirmed = await showConfirm(
      context,
      sent
          ? 'Cette action supprime la proposition et ses photos de cet '
                'appareil. Les données déjà envoyées restent sur le serveur.'
          : 'Cette action annule l’envoi et supprime les photos locales.',
      titre: 'Supprimer la proposition ?',
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    final result = await ref
        .read(mineSubmissionActionsProvider)
        .delete(widget.submission.payloadId);
    if (!mounted) return;
    await result.match(
      (failure) => showAppMessage(
        context,
        'Impossible de supprimer la proposition',
        kind: AppMsgKind.error,
      ),
      (_) async => Navigator.of(context).pop(true),
    );
    if (mounted) setState(() => _deleting = false);
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;
    final status = _submissionStatus(submission.state);
    final date = DateFormat('dd/MM/yyyy HH:mm').format(submission.createdAt);
    final canSend =
        submission.state == MineSubmissionState.localPending ||
        submission.state == MineSubmissionState.awaitingAttachments;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.86,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Détails de la proposition',
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
            const SizedBox(height: 8),
            Text(
              submission.nom,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            StatusPill(kind: status.kind, label: status.label),
            const SizedBox(height: 18),
            _DetailRow(label: 'Créée le', value: date),
            if (submission.communeId != null)
              _DetailRow(
                label: 'Commune historique',
                value: '#${submission.communeId}',
              ),
            _DetailRow(label: 'Payload', value: submission.payloadId),
            if (submission.serverId != null)
              _DetailRow(
                label: 'ID serveur',
                value: submission.serverId.toString(),
              ),
            const SizedBox(height: 18),
            Text(
              'Positions photographiées',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            for (final part in submission.photos) ...[
              _SubmissionPhotoCard(part: part),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 12),
            if (canSend) ...[
              BigButton(
                icon: Icons.cloud_upload_outlined,
                label: _sending
                    ? 'Envoi en cours…'
                    : submission.state == MineSubmissionState.localPending
                    ? 'Envoyer maintenant'
                    : 'Renvoyer les photos',
                onPressed: _sending || _deleting ? null : _sendNow,
              ),
              const SizedBox(height: 10),
            ],
            BigButton(
              icon: Icons.delete_outline,
              label: _deleting ? 'Suppression…' : 'Supprimer de cet appareil',
              color: AppColors.danger,
              onPressed: _deleting || _sending ? null : _delete,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _SubmissionPhotoCard extends StatelessWidget {
  final MineSubmissionPhoto part;

  const _SubmissionPhotoCard({required this.part});

  @override
  Widget build(BuildContext context) {
    final photo = part.photo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhotoThumb(path: photo.path, size: 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(part.key, style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    '${photo.lat.toStringAsFixed(5)}, '
                    '${photo.lon.toStringAsFixed(5)}',
                  ),
                  Text('Précision ±${photo.precision.toStringAsFixed(1)} m'),
                  if (photo.headingDegrees != null)
                    Text(
                      'Cap ${photo.headingDegrees!.round()}° '
                      '${_cardinal(photo.headingDegrees!)}',
                    ),
                  Text(
                    part.uploaded ? 'Photo envoyée' : 'Photo à envoyer',
                    style: TextStyle(
                      color: part.uploaded ? AppColors.ok : AppColors.warn,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _cardinal(double degrees) {
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  return directions[((degrees % 360) / 45).round() % directions.length];
}

class _EmptySubmissions extends StatelessWidget {
  const _EmptySubmissions();

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 120),
      const Icon(
        Icons.add_location_alt_outlined,
        size: 72,
        color: AppColors.inkSoft,
      ),
      const SizedBox(height: 16),
      Text(
        'Aucune mine proposée',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      const Text(
        'Les propositions restent indisponibles\ntant que le serveur ne les a pas validées.',
        textAlign: TextAlign.center,
      ),
    ],
  );
}
