import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_details.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/update/app_update_service.dart';
import '../../../shared/ui/ui_kit.dart';
import 'app_update_provider.dart';

class AppUpdateBanner extends ConsumerWidget {
  final Widget child;

  const AppUpdateBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final update = state.update;
    if (update == null) return child;

    final color = update.mandatory ? AppColors.danger : AppColors.gold;
    return Column(
      children: [
        Material(
          color: color.withValues(alpha: 0.14),
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: state.downloading
                  ? null
                  : () => openAvailableAppUpdate(context, ref, update),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                child: Row(
                  children: [
                    Icon(Icons.system_update_alt, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        update.mandatory
                            ? 'Mise à jour obligatoire ${update.version} disponible'
                            : 'Mise à jour ${update.version} disponible',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: state.downloading
                          ? null
                          : () => openAvailableAppUpdate(context, ref, update),
                      child: const Text('Mettre à jour'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

Future<void> checkAndOpenAppUpdate(BuildContext context, WidgetRef ref) async {
  try {
    final check = await ref
        .read(appUpdateControllerProvider.notifier)
        .check(silent: false);
    if (!context.mounted || check == null) return;
    final update = check.update;
    if (update == null) {
      await showAppMessage(
        context,
        'La version ${check.currentVersion} (${check.currentBuild}) est à jour.',
        kind: AppMsgKind.success,
      );
      return;
    }
    await openAvailableAppUpdate(context, ref, update);
  } catch (error) {
    if (!context.mounted) return;
    await showAppMessage(
      context,
      apiErrorDetails(error),
      kind: AppMsgKind.error,
      titre: 'Mise à jour impossible',
    );
  }
}

Future<void> openAvailableAppUpdate(
  BuildContext context,
  WidgetRef ref,
  AppUpdateInfo update,
) async {
  final controller = ref.read(appUpdateControllerProvider.notifier);
  try {
    final pending = await controller.refreshUnsyncedDataCount();
    if (!context.mounted) return;
    if (pending > 0) {
      await showAppMessage(
        context,
        'La mise à jour est bloquée car des données locales ne sont pas encore '
        'synchronisées. Lancez la synchronisation, puis réessayez.',
        kind: AppMsgKind.warning,
        titre: 'Synchronisation requise',
      );
      return;
    }

    final accepted = await showConfirm(
      context,
      [
        'Version ${update.version} (${update.build}) disponible.',
        if (update.releaseNotes?.trim().isNotEmpty == true)
          update.releaseNotes!.trim(),
        if (update.mandatory)
          'Cette mise à jour est obligatoire.'
        else
          'Vous pouvez l’installer maintenant.',
        'Android demandera de confirmer l’installation.',
      ].join('\n\n'),
      titre: update.mandatory ? 'Mise à jour obligatoire' : 'Nouvelle version',
      confirmLabel: 'Télécharger',
    );
    if (!accepted || !context.mounted) return;

    final status = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _UpdateDownloadSheet(update: update),
    );
    if (!context.mounted || status == null) return;
    if (status == 'permission_required') {
      await showAppMessage(
        context,
        'Autorisez MICA Fleet à installer des applications, puis appuyez de '
        'nouveau sur « Mettre à jour ».',
        kind: AppMsgKind.warning,
      );
    } else {
      showAppToast(context, 'Installateur Android ouvert');
    }
  } catch (error) {
    if (!context.mounted) return;
    final message = error is UnsyncedDataBeforeUpdate
        ? 'Des données locales attendent encore leur synchronisation.'
        : apiErrorDetails(error);
    await showAppMessage(
      context,
      message,
      kind: AppMsgKind.error,
      titre: 'Mise à jour impossible',
    );
  }
}

class _UpdateDownloadSheet extends ConsumerStatefulWidget {
  final AppUpdateInfo update;

  const _UpdateDownloadSheet({required this.update});

  @override
  ConsumerState<_UpdateDownloadSheet> createState() =>
      _UpdateDownloadSheetState();
}

class _UpdateDownloadSheetState extends ConsumerState<_UpdateDownloadSheet> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _download());
  }

  Future<void> _download() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final status = await ref
          .read(appUpdateControllerProvider.notifier)
          .downloadAndInstall(widget.update);
      if (mounted) Navigator.of(context).pop(status);
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorDetails(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateControllerProvider);
    final progress = state.progress;
    final downloading = state.downloading || _error == null;
    return PopScope(
      canPop: !downloading,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Téléchargement de la mise à jour',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (!downloading)
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error == null) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 12),
              Text(
                progress == null
                    ? 'Préparation du téléchargement…'
                    : '${(progress * 100).clamp(0, 100).round()} %',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Version ${widget.update.version} (${widget.update.build})',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else ...[
              const Icon(
                Icons.error_outline,
                color: AppColors.danger,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              BigButton(
                icon: Icons.refresh,
                label: 'Réessayer',
                onPressed: _download,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
