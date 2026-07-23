import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';
import '../sync_history_provider.dart';
import '../sync_provider.dart';

/// Détail d'une opération de synchronisation : toutes ses métadonnées + le
/// contenu JSON exact envoyé (ou à envoyer) à Odoo.
class SyncDetailScreen extends ConsumerWidget {
  final String opId;
  const SyncDetailScreen({super.key, required this.opId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final op = ref.watch(syncOpProvider(opId));
    final df = DateFormat('dd/MM/yyyy HH:mm:ss');

    return Scaffold(
      appBar: AppBar(title: const Text('Détail de l\'envoi')),
      body: op.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (h) {
          if (h == null) {
            return const Center(child: Text('Opération introuvable'));
          }
          final json = _prettyJson(h.payload);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(h.entityId,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  _statutPill(h.status),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _kv('Type', '${h.entityType} · ${h.opType}'),
                    _kv('Identifiant', h.opId),
                    if (h.agentLogin != null) _kv('Agent', h.agentLogin!),
                    _kv('Créé', df.format(h.createdAt)),
                    if (h.syncedAt != null) _kv('Envoyé', df.format(h.syncedAt!)),
                    if (h.odooId != null) _kv('Réf. Odoo', '#${h.odooId}'),
                    if (h.status != 'synced') _kv('Tentatives', '${h.attempts}'),
                    if (h.nextRetryAt != null && h.status != 'synced')
                      _kv('Prochain essai', df.format(h.nextRetryAt!)),
                  ]),
                ),
              ),
              if (h.lastError != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: AppColors.danger.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dernière erreur',
                            style: TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(h.lastError!,
                            style: const TextStyle(color: AppColors.danger)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child:
                        StepHeader(numero: 1, titre: 'Données envoyées (JSON)'),
                  ),
                  IconButton(
                    tooltip: 'Copier',
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: json));
                      if (context.mounted) {
                        await showAppMessage(context, 'JSON copié',
                            kind: AppMsgKind.success);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  json,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12, height: 1.4),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: op.maybeWhen(
        data: (h) => (h != null && h.status != 'synced' && h.status != 'syncing')
            ? SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: BigButton(
                  icon: Icons.cloud_upload,
                  label: 'Réessayer maintenant',
                  onPressed: () async {
                    await ref.read(triggerSyncProvider).sync();
                    ref.invalidate(syncOpProvider(opId));
                    ref.invalidate(syncHistoryProvider);
                  },
                ),
              )
            : null,
        orElse: () => null,
      ),
    );
  }
}

String _prettyJson(String raw) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {
    return raw; // payload non-JSON : on montre brut
  }
}

Widget _statutPill(String s) => switch (s) {
      'synced' => const StatusPill(kind: PillKind.ok, label: 'Envoyé'),
      'failed' => const StatusPill(kind: PillKind.danger, label: 'Échec'),
      'syncing' => const StatusPill(kind: PillKind.neutral, label: 'En cours'),
      _ => const StatusPill(kind: PillKind.warn, label: 'En attente'),
    };

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(k, style: const TextStyle(color: AppColors.inkSoft))),
          Expanded(
            child: Text(v,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
