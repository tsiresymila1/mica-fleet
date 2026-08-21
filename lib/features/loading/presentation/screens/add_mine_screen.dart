import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/capture_photo_screen.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../../capture/domain/entities/traceability_photos.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../../mines/domain/entities/mine.dart';
import '../../../mines/domain/entities/mine_submission.dart';
import '../../../mines/presentation/providers/mine_submissions_provider.dart';
import '../../../mines/presentation/providers/mines_provider.dart';
import '../../../trip/presentation/sim_session.dart';
import '../../domain/entities/lot.dart';

/// Création d'un lot chargé depuis une mine existante.
class AddMineScreen extends ConsumerStatefulWidget {
  const AddMineScreen({super.key});
  @override
  ConsumerState<AddMineScreen> createState() => _AddMineScreenState();
}

class _AddMineScreenState extends ConsumerState<AddMineScreen> {
  _MineChoice? _mineChoice;
  CapturedPhoto? _platePhoto;
  CapturedPhoto? _truckPhoto;
  final _couleurCtrl = TextEditingController();
  final _qteCtrl = TextEditingController();
  final _plaqueCtrl = TextEditingController();

  @override
  void dispose() {
    _couleurCtrl.dispose();
    _qteCtrl.dispose();
    _plaqueCtrl.dispose();
    super.dispose();
  }

  Future<void> _capture(TraceabilityPhotoRole role) async {
    final title = switch (role) {
      TraceabilityPhotoRole.plate => 'Chargement mine — plaque',
      TraceabilityPhotoRole.mica => 'Chargement mine — mica',
      TraceabilityPhotoRole.truckWithMica =>
        'Chargement mine — camion avec mica',
    };
    final photo = await Navigator.of(context).push<CapturedPhoto>(
      MaterialPageRoute(builder: (_) => CapturePhotoScreen(titre: title)),
    );
    if (photo == null) return;

    String? plaque;
    if (role == TraceabilityPhotoRole.plate) {
      // Seule la preuve plaque alimente l'OCR.
      final sim = ref.read(simSessionProvider);
      plaque = sim != null
          ? ref.read(simSessionProvider.notifier).plate
          : await ref.read(plateOcrServiceProvider).readPlate(photo.path);
    }
    if (!mounted) return;
    setState(() {
      switch (role) {
        case TraceabilityPhotoRole.plate:
          _platePhoto = photo;
          break;
        case TraceabilityPhotoRole.mica:
          break;
        case TraceabilityPhotoRole.truckWithMica:
          _truckPhoto = photo;
          break;
      }
      if (plaque != null) _plaqueCtrl.text = plaque;
    });
  }

  int get _capturedPhotoCount =>
      [_platePhoto, _truckPhoto].whereType<CapturedPhoto>().length;

  bool get _canSave =>
      _mineChoice != null &&
      _mineChoice!.id.isNotEmpty &&
      _capturedPhotoCount == 2;

  Future<void> _openMinePicker(
    List<_MineChoice> mines,
    String? currentId,
  ) async {
    final selected = await showModalBottomSheet<_MineChoice>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _MineSelectionSheet(mines: mines, currentId: currentId),
    );
    if (selected == null || !mounted) return;
    setState(() => _mineChoice = selected);
  }

  void _save() {
    if (_mineChoice == null || _platePhoto == null || _truckPhoto == null) {
      showAppMessage(
        context,
        'Choisis la mine et prends les 2 photos obligatoires',
        kind: AppMsgKind.warning,
      );
      return;
    }
    // L'id définitif du lot est attribué par AddChargementScreen (<session>-L<n>).
    Navigator.of(context).pop(
      Lot(
        id: '',
        mineId: _mineChoice!.id,
        couleur: _couleurCtrl.text.trim().isEmpty
            ? null
            : _couleurCtrl.text.trim(),
        quantiteEstimee: double.tryParse(_qteCtrl.text.replaceAll(',', '.')),
        plaqueDepart: _plaqueCtrl.text.trim().isEmpty
            ? null
            : _plaqueCtrl.text.trim(),
        photos: TraceabilityPhotos(
          plate: _platePhoto!,
          truckWithMica: _truckPhoto!,
        ),
      ),
    );
  }

  List<_MineChoice> _buildMineOptions(
    List<Mine> mines,
    List<dynamic> submissions,
  ) {
    final mineOptions = mines
        .map(
          (mine) => _MineChoice(
            id: mine.id,
            name: mine.nom,
            reference: mine.reference,
            note: mine.note,
            district: mine.district,
            commune: mine.commune,
            fokontany: mine.fokontany,
            lat: mine.lat,
            lon: mine.lon,
            createdAt: mine.createdAt,
            fromSubmission: false,
          ),
        )
        .toList();

    final localMineOptions = submissions
        .whereType<_MineSubmissionPreview>()
        .map(
          (submission) => _MineChoice(
            id: submission.id,
            name: submission.name,
            reference: submission.reference,
            note: submission.note,
            lat: submission.lat,
            lon: submission.lon,
            createdAt: submission.createdAt,
            fromSubmission: true,
          ),
        )
        .toList();

    final options = [...mineOptions, ...localMineOptions];
    options.sort(_compareMineChoiceCreatedAtDescending);
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final minesAsync = ref.watch(minesProvider);
    final submissionsAsync = ref.watch(mineSubmissionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chargement à la mine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          StepHeader(
            numero: 1,
            titre: 'La mine',
            sousTitre: 'Choisis la mine d’origine de ce lot',
          ),
          const SizedBox(height: 12),
          if (minesAsync.isLoading || submissionsAsync.isLoading)
            const LinearProgressIndicator()
          else if (minesAsync.hasError || submissionsAsync.hasError)
            const Text('Impossible de charger les mines')
          else
            Builder(
              builder: (context) {
                final mineOptions = _buildMineOptions(
                  minesAsync.value ?? const [],
                  (submissionsAsync.value ?? const [])
                      .where(
                        (s) =>
                            s.serverId == null &&
                            (s.state == MineSubmissionState.localPending ||
                                s.state ==
                                    MineSubmissionState.awaitingAttachments ||
                                s.state ==
                                    MineSubmissionState.pendingValidation),
                      )
                      .map(
                        (s) => _MineSubmissionPreview(
                          id: s.payloadId,
                          name: s.nom,
                          reference: null,
                          note: null,
                          createdAt: s.createdAt,
                          lat: s.photos.isNotEmpty
                              ? s.photos.first.photo.lat
                              : null,
                          lon: s.photos.isNotEmpty
                              ? s.photos.first.photo.lon
                              : null,
                        ),
                      )
                      .toList(),
                );
                if (mineOptions.isEmpty) {
                  return const Text(
                    'Aucune mine disponible. Propose d’abord une mine.',
                  );
                }

                if (_mineChoice == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _mineChoice = mineOptions.first);
                    }
                  });
                } else if (!mineOptions.any((m) => m.id == _mineChoice!.id)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _mineChoice = mineOptions.first);
                    }
                  });
                }

                final mine = _mineChoice != null
                    ? mineOptions.firstWhere(
                        (m) => m.id == _mineChoice!.id,
                        orElse: () => mineOptions.first,
                      )
                    : mineOptions.first;

                return InkWell(
                  onTap: () => _openMinePicker(mineOptions, mine.id),
                  borderRadius: BorderRadius.circular(12),
                  child: ActionTile(
                    icon: Icons.terrain,
                    color: AppColors.gold,
                    titre: mine.name,
                    sousTitre: mine.summary,
                    trailing: const Icon(Icons.search),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          StepHeader(
            numero: 2,
            titre: 'Photos du chargement — $_capturedPhotoCount/2',
            sousTitre: 'Appuie sur chaque ligne pour prendre la photo demandée',
          ),
          const SizedBox(height: 12),
          PhotoCaptureProgress(captured: _capturedPhotoCount, total: 2),
          const SizedBox(height: 12),
          _CaptureTile(
            title: 'Photo de la plaque',
            subtitle: 'Utilisée pour la reconnaissance de plaque',
            photo: _platePhoto,
            onTap: () => _capture(TraceabilityPhotoRole.plate),
          ),
          const SizedBox(height: 10),
          _CaptureTile(
            title: 'Photo du camion avec mica',
            subtitle: 'Vue d’ensemble du camion chargé',
            photo: _truckPhoto,
            onTap: () => _capture(TraceabilityPhotoRole.truckWithMica),
          ),
          const SizedBox(height: 24),
          StepHeader(numero: 3, titre: 'Les détails'),
          const SizedBox(height: 12),
          TextField(
            controller: _plaqueCtrl,
            decoration: const InputDecoration(
              labelText: 'Plaque du camion',
              prefixIcon: Icon(Icons.directions_car),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _couleurCtrl,
            decoration: const InputDecoration(
              labelText: 'Couleur du mica',
              prefixIcon: Icon(Icons.palette),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qteCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Quantité estimée (kg)',
              prefixIcon: Icon(Icons.scale),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: BigButton(
          icon: Icons.check,
          label: 'Enregistrer le lot',
          onPressed: _canSave ? _save : null,
        ),
      ),
    );
  }
}

class _MineChoice {
  const _MineChoice({
    required this.id,
    required this.name,
    required this.fromSubmission,
    this.reference,
    this.note,
    this.district,
    this.commune,
    this.fokontany,
    this.lat,
    this.lon,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? reference;
  final String? note;
  final String? district;
  final String? commune;
  final String? fokontany;
  final double? lat;
  final double? lon;
  final DateTime? createdAt;
  final bool fromSubmission;

  String get summary {
    final parts = <String>[
      if (reference?.trim().isNotEmpty == true) 'Réf. ${reference!.trim()}',
      if (note?.trim().isNotEmpty == true) 'Note: ${note!.trim()}',
      if (fokontany?.trim().isNotEmpty == true)
        'Fokontany: ${fokontany!.trim()}',
      if (commune?.trim().isNotEmpty == true) commune!.trim(),
      if (district?.trim().isNotEmpty == true) district!.trim(),
      if (lat != null && lon != null)
        'GPS ${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}',
      if (createdAt != null)
        'Créé le ${createdAt!.day.toString().padLeft(2, '0')}/'
            '${createdAt!.month.toString().padLeft(2, '0')}/${createdAt!.year}',
      if (fromSubmission) 'Créée manuellement (non validée)',
    ];
    return parts.join('  •  ');
  }
}

int _compareMineChoiceCreatedAtDescending(
  _MineChoice first,
  _MineChoice second,
) {
  final firstDate = first.createdAt;
  final secondDate = second.createdAt;
  if (firstDate == null && secondDate == null) {
    return first.name.compareTo(second.name);
  }
  if (firstDate == null) return 1;
  if (secondDate == null) return -1;

  final byDate = secondDate.compareTo(firstDate);
  return byDate != 0 ? byDate : first.name.compareTo(second.name);
}

class _MineSubmissionPreview {
  const _MineSubmissionPreview({
    required this.id,
    required this.name,
    this.reference,
    this.note,
    this.createdAt,
    this.lat,
    this.lon,
  });

  final String id;
  final String name;
  final String? reference;
  final String? note;
  final DateTime? createdAt;
  final double? lat;
  final double? lon;
}

class _MineSelectionSheet extends StatefulWidget {
  const _MineSelectionSheet({required this.mines, required this.currentId});

  final List<_MineChoice> mines;
  final String? currentId;

  @override
  State<_MineSelectionSheet> createState() => _MineSelectionSheetState();
}

class _MineSelectionSheetState extends State<_MineSelectionSheet> {
  final _queryCtrl = TextEditingController();

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _queryCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.mines
        : widget.mines.where((mine) {
            final haystack =
                '${mine.name} ${mine.reference ?? ''} ${mine.note ?? ''} '
                        '${mine.district ?? ''} ${mine.commune ?? ''} '
                        '${mine.fokontany ?? ''}'
                    .toLowerCase();
            return haystack.contains(q);
          }).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            TextField(
              controller: _queryCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Rechercher une mine',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Aucun résultat'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final mine = filtered[index];
                        final selected = mine.id == widget.currentId;
                        return ListTile(
                          leading: Icon(
                            mine.fromSubmission
                                ? Icons.pending_actions
                                : Icons.terrain,
                            color: selected
                                ? AppColors.primary
                                : AppColors.inkSoft,
                          ),
                          title: Text(mine.name),
                          subtitle: Text(
                            mine.summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: selected,
                          onTap: () => Navigator.of(context).pop(mine),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final CapturedPhoto? photo;
  final VoidCallback onTap;

  const _CaptureTile({
    required this.title,
    required this.subtitle,
    required this.photo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ActionTile(
    icon: photo == null ? Icons.camera_alt_outlined : Icons.check_circle,
    color: photo == null ? AppColors.primary : AppColors.ok,
    titre: title,
    sousTitre: photo == null
        ? '$subtitle\nAppuyer pour prendre la photo'
        : 'GPS ${photo!.lat.toStringAsFixed(4)}, '
              '${photo!.lon.toStringAsFixed(4)} — appuyer pour reprendre',
    onTap: onTap,
    trailing: photo != null && File(photo!.path).existsSync()
        ? ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(photo!.path),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          )
        : null,
  );
}
