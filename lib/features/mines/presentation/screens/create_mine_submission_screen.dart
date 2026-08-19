import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/photo_view.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../data/repositories/mine_submission_repository_impl.dart';
import '../providers/mine_submissions_provider.dart';

final _activeCommunesProvider = FutureProvider<List<CommuneRow>>((ref) async {
  final db = ref.watch(dbProvider);
  return (db.select(db.communes)..where((c) => c.actif.equals(true))).get();
});

class CreateMineSubmissionScreen extends ConsumerStatefulWidget {
  const CreateMineSubmissionScreen({super.key});

  @override
  ConsumerState<CreateMineSubmissionScreen> createState() =>
      _CreateMineSubmissionScreenState();
}

class _CreateMineSubmissionScreenState
    extends ConsumerState<CreateMineSubmissionScreen> {
  final _nameController = TextEditingController();
  CommuneRow? _selectedCommune;
  final List<CapturedPhoto> _photos = [];
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
    setState(() => _saving = true);
    final agent = ref.read(authControllerProvider);
    final result = await ref
        .read(createMineSubmissionProvider)
        .create(
          name: _nameController.text,
          photos: List.unmodifiable(_photos),
          agentLogin: agent?.id,
          communeId: _selectedCommune?.id,
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

  Future<void> _selectCommune() async {
    final communes = await ref.read(_activeCommunesProvider.future);
    if (!mounted) return;
    if (communes.isEmpty) {
      showAppMessage(
        context,
        'Aucune commune en cache. Connectez-vous pour les charger.',
        kind: AppMsgKind.warning,
      );
      return;
    }

    final selected = await showModalBottomSheet<CommuneRow?>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      useSafeArea: true,
      builder: (_) => _CommunePickerSheet(
        communes: communes,
        currentId: _selectedCommune?.id,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedCommune = selected);
  }

  String? get _selectedCommuneLabel => _selectedCommune == null
      ? null
      : '${_selectedCommune!.nom} (${_selectedCommune!.district ?? 'District inconnu'})';

  @override
  Widget build(BuildContext context) {
    final enough = _photos.length >= MineSubmissionRepositoryImpl.minPhotos;
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
          const SizedBox(height: 8),
          const Text(
            'Le fokontany, la commune et la région seront déterminés par le serveur à partir des positions GPS.',
          ),
          const SizedBox(height: 16),
          ActionTile(
            icon: Icons.location_city_outlined,
            titre: 'Commune',
            color: AppColors.primary,
            sousTitre: _selectedCommuneLabel ?? 'Sélectionner une commune',
            onTap: _selectCommune,
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
          onPressed: _saving || !enough || _nameController.text.trim().isEmpty
              ? null
              : _save,
        ),
      ),
    );
  }
}

class _CommunePickerSheet extends ConsumerStatefulWidget {
  final List<CommuneRow> communes;
  final int? currentId;
  const _CommunePickerSheet({
    required this.communes,
    required this.currentId,
  });

  @override
  ConsumerState<_CommunePickerSheet> createState() => _CommunePickerSheetState();
}

class _CommunePickerSheetState extends ConsumerState<_CommunePickerSheet> {
  final _query = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _text.trim().toLowerCase();
    final rows = widget.communes.where((commune) {
      if (q.isEmpty) return true;
      final haystack =
          '${commune.nom} ${commune.district ?? ''}'.toLowerCase();
      return haystack.contains(q);
    }).toList()
      ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
            child: TextField(
              controller: _query,
              onChanged: (value) => setState(() => _text = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher une commune',
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final commune = rows[index];
                return ListTile(
                  dense: true,
                  title: Text(commune.nom),
                  subtitle: commune.district == null
                      ? null
                      : Text(commune.district!),
                  trailing: commune.id == widget.currentId
                      ? const Icon(Icons.check, color: AppColors.ok)
                      : null,
                  onTap: () => Navigator.of(context).pop(commune),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
