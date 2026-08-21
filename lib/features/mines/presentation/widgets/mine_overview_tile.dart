import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/ui/ui_kit.dart';

/// Aperçu commun aux mines validées et aux propositions locales.
class MineOverviewTile extends StatelessWidget {
  const MineOverviewTile({
    super.key,
    required this.name,
    required this.createdAt,
    this.reference,
    this.note,
    this.details = const [],
    this.icon = Icons.terrain,
    this.color = AppColors.gold,
    this.trailing,
    this.onTap,
  });

  final String name;
  final String? reference;
  final String? note;
  final DateTime? createdAt;
  final List<String> details;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;

  String _valueOrDash(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? '—' : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final date = createdAt == null
        ? '—'
        : DateFormat('dd/MM/yyyy').format(createdAt!);
    return ActionTile(
      icon: icon,
      color: color,
      titre: name,
      sousTitre: [
        'Référence : ${_valueOrDash(reference)}',
        'Créée le : $date',
        'Note : ${_valueOrDash(note)}',
        ...details.where((detail) => detail.trim().isNotEmpty),
      ].join('\n'),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
