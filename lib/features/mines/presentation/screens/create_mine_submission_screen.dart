import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/photo_view.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../data/repositories/mine_submission_repository_impl.dart';
import '../providers/mine_submissions_provider.dart';

class CreateMineSubmissionScreen extends ConsumerStatefulWidget {
  const CreateMineSubmissionScreen({super.key});

  @override
  ConsumerState<CreateMineSubmissionScreen> createState() =>
      _CreateMineSubmissionScreenState();
}

class _CreateMineSubmissionScreenState
    extends ConsumerState<CreateMineSubmissionScreen> {
  final _nameController = TextEditingController();
  final List<CapturedPhoto> _photos = [];
  int? _communeId;
  bool _saving = false;

  @override
  void dispose() {
    for (final photo in _photos) {
      try {
        File(photo.path).deleteSync();
      } catch (_) {
        // Fichier déjà déplacé/purgé ou cache indisponible.
      }
    }
    _nameController.dispose();
    super.dispose();
  }

  void _removePhoto(int index) {
    final photo = _photos.removeAt(index);
    try {
      File(photo.path).deleteSync();
    } catch (_) {
      // La suppression visuelle ne doit pas bloquer l'utilisateur.
    }
    setState(() {});
  }

  Future<void> _capture() async {
    final photo = await context.push<CapturedPhoto>(
      '/capture-photo?title=${Uri.encodeQueryComponent('Position ${_photos.length + 1}')}',
    );
    if (photo != null && mounted) setState(() => _photos.add(photo));
  }

  Future<void> _save() async {
    if (_saving) return;
    final communeId = _communeId;
    if (communeId == null) {
      await showAppMessage(
        context,
        'Sélectionne une commune',
        kind: AppMsgKind.error,
      );
      return;
    }
    setState(() => _saving = true);
    final agent = ref.read(authControllerProvider);
    final result = await ref
        .read(createMineSubmissionProvider)
        .create(
          name: _nameController.text,
          communeId: communeId,
          photos: List.unmodifiable(_photos),
          agentLogin: agent?.id,
        );
    if (!mounted) return;
    await result.match(
      (failure) => showAppMessage(
        context,
        failure is ValidationFailure
            ? failure.message
            : 'Impossible de sauvegarder la proposition',
        kind: AppMsgKind.error,
      ),
      (_) async {
        await showAppMessage(
          context,
          'Mine sauvegardée. Elle sera utilisable après validation.',
          kind: AppMsgKind.success,
        );
        if (mounted) context.pop(true);
      },
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final enough = _photos.length >= MineSubmissionRepositoryImpl.minPhotos;
    final communes = ref.watch(communesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Proposer une mine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          const StepHeader(
            numero: 1,
            titre: 'Informations',
            sousTitre: 'La mine restera indisponible jusqu’à sa validation.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nom de la mine',
              prefixIcon: Icon(Icons.landscape_outlined),
            ),
          ),
          const SizedBox(height: 14),
          communes.when(
            data: (items) {
              if (items.isEmpty) {
                return const _EmptyCommuneCache();
              }
              return DropdownMenu<int>(
                expandedInsets: EdgeInsets.zero,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                label: const Text('Commune'),
                leadingIcon: const Icon(Icons.location_city_outlined),
                hintText: 'Rechercher une commune',
                dropdownMenuEntries: [
                  for (final commune in items)
                    DropdownMenuEntry<int>(
                      value: commune.id,
                      label: commune.district == null
                          ? commune.nom
                          : '${commune.nom} — ${commune.district}',
                    ),
                ],
                onSelected: (value) => setState(() => _communeId = value),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Row(
              children: [
                const Expanded(
                  child: Text('Impossible de lire les communes en cache.'),
                ),
                IconButton(
                  tooltip: 'Réessayer',
                  onPressed: () => ref.invalidate(communesProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          StepHeader(
            numero: 2,
            titre: 'Positions photographiées',
            sousTitre:
                '${_photos.length}/5 minimum — GPS et hash enregistrés automatiquement',
          ),
          const SizedBox(height: 14),
          if (_photos.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var index = 0; index < _photos.length; index++)
                  _PhotoPositionTile(
                    index: index,
                    photo: _photos[index],
                    onDelete: () => _removePhoto(index),
                  ),
              ],
            ),
          if (_photos.isNotEmpty) const SizedBox(height: 16),
          BigButton(
            icon: Icons.add_a_photo_outlined,
            label: 'Ajouter la position ${_photos.length + 1}',
            color: enough ? AppColors.gold : null,
            onPressed: _capture,
          ),
          const SizedBox(height: 12),
          StatusPill(
            kind: enough ? PillKind.ok : PillKind.warn,
            label: enough
                ? 'Nombre minimum atteint'
                : '${MineSubmissionRepositoryImpl.minPhotos - _photos.length} photo(s) restante(s)',
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
          icon: Icons.save_outlined,
          label: _saving ? 'Enregistrement…' : 'Enregistrer localement',
          onPressed:
              _saving ||
                  !enough ||
                  _nameController.text.trim().isEmpty ||
                  _communeId == null
              ? null
              : _save,
        ),
      ),
    );
  }
}

class _EmptyCommuneCache extends StatelessWidget {
  const _EmptyCommuneCache();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      'Aucune commune disponible. Connecte-toi une première fois pour '
      'charger le référentiel.',
    ),
  );
}

class _PhotoPositionTile extends StatelessWidget {
  final int index;
  final CapturedPhoto photo;
  final VoidCallback onDelete;

  const _PhotoPositionTile({
    required this.index,
    required this.photo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhotoThumb(path: photo.path, size: 52),
                const Spacer(),
                IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close, color: AppColors.danger),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Position ${index + 1}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '${photo.lat.toStringAsFixed(5)}, ${photo.lon.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '±${photo.precision.toStringAsFixed(1)} m',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (photo.headingDegrees != null)
              Text(
                'Cap ${photo.headingDegrees!.round()}° ${_cardinal(photo.headingDegrees!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    ),
  );
}

String _cardinal(double degrees) {
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  return directions[((degrees % 360) / 45).round() % directions.length];
}
