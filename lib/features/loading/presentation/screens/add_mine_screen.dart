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
  Mine? _mine;
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

  bool get _canSave => _mine != null && _capturedPhotoCount == 2;

  void _save() {
    if (_mine == null || _platePhoto == null || _truckPhoto == null) {
      showAppMessage(
        context,
        'Choisis la mine et prends les 2 photos obligatoires',
        kind: AppMsgKind.warning,
      );
      return;
    }
    // L'id définitif du lot est attribué par AddLotToChargement (<session>-L<n>).
    Navigator.of(context).pop(
      Lot(
        id: '',
        mineId: _mine!.id,
        // Référence fournisseur masquée pour l'instant (voir demande produit).
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

  @override
  Widget build(BuildContext context) {
    final minesAsync = ref.watch(minesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Chargement à la mine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          StepHeader(
            numero: 1,
            titre: 'La mine',
            sousTitre: 'Sélectionne la mine d’origine de ce lot',
          ),
          const SizedBox(height: 12),
          minesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const Text('Impossible de charger les mines'),
            data: (mines) {
              if (ref.read(simSessionProvider) != null &&
                  _mine == null &&
                  mines.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _mine = mines.first);
                });
              }
              return DropdownButtonFormField<Mine>(
                initialValue: _mine,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Choisir la mine',
                  prefixIcon: Icon(Icons.landscape),
                ),
                items: mines
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.nom)))
                    .toList(),
                onChanged: (m) => setState(() => _mine = m),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _capturedPhotoCount / 2,
              minHeight: 6,
              backgroundColor: AppColors.inkSoft.withValues(alpha: 0.15),
            ),
          ),
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
