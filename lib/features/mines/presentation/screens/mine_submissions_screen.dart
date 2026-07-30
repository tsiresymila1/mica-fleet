import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../domain/entities/mine_submission.dart';
import '../providers/mine_submissions_provider.dart';
import '../providers/mines_provider.dart';

class MineSubmissionsScreen extends ConsumerWidget {
  const MineSubmissionsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(syncEngineProvider).sync();
    ref.invalidate(mineSubmissionsProvider);
    ref.invalidate(minesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissions = ref.watch(mineSubmissionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mines proposées'),
        actions: [
          IconButton(
            tooltip: 'Synchroniser',
            icon: const Icon(Icons.sync),
            onPressed: () => _refresh(ref),
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
                  itemBuilder: (_, index) => _SubmissionTile(items[index]),
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
  const _SubmissionTile(this.submission);

  @override
  Widget build(BuildContext context) {
    final uploaded = submission.photos.where((p) => p.uploaded).length;
    final (label, kind, color, icon) = switch (submission.state) {
      MineSubmissionState.localPending => (
        'À envoyer',
        PillKind.warn,
        AppColors.warn,
        Icons.cloud_upload_outlined,
      ),
      MineSubmissionState.awaitingAttachments => (
        'Photos $uploaded/${submission.photos.length}',
        PillKind.neutral,
        AppColors.inkSoft,
        Icons.cloud_sync_outlined,
      ),
      MineSubmissionState.pendingValidation => (
        'En validation',
        PillKind.neutral,
        AppColors.primary,
        Icons.fact_check_outlined,
      ),
      MineSubmissionState.approved => (
        'Validée',
        PillKind.ok,
        AppColors.ok,
        Icons.verified_outlined,
      ),
      MineSubmissionState.rejected => (
        'Refusée',
        PillKind.danger,
        AppColors.danger,
        Icons.block_outlined,
      ),
    };
    final date = DateFormat('dd/MM/yyyy HH:mm').format(submission.createdAt);
    return ActionTile(
      icon: icon,
      color: color,
      titre: submission.nom,
      sousTitre: [
        '${submission.photos.length} positions',
        date,
        if (submission.rejectionReason != null) submission.rejectionReason!,
      ].join(' • '),
      trailing: StatusPill(kind: kind, label: label),
    );
  }
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
