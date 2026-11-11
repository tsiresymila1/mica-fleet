import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/chargements_list_provider.dart';

enum LotFilterField {
  tonnage('Tonnage (kg)', _Kind.number),
  score('Score', _Kind.number),
  date('Date', _Kind.date),
  mine('Mine', _Kind.text),
  depot('Dépôt', _Kind.text),
  plaque('Plaque', _Kind.text),
  statut('Statut', _Kind.statut);

  final String label;
  final _Kind _kind;
  const LotFilterField(this.label, this._kind);

  bool get ordered => _kind == _Kind.number || _kind == _Kind.date;
}

enum _Kind { number, date, text, statut }

enum LotFilterOp {
  eq('='),
  ne('≠'),
  gt('>'),
  lt('<'),
  gte('≥'),
  lte('≤');

  final String label;
  const LotFilterOp(this.label);
}

const _statuts = {
  'pending': 'En attente',
  'validated': 'Validé',
  'rejected': 'Rejeté',
};

class LotFilterRule {
  final LotFilterField field;
  final LotFilterOp op;
  final String value;
  const LotFilterRule(this.field, this.op, this.value);

  bool matches(LotListItem lot) {
    if (value.isEmpty) return true;
    final int? cmp = switch (field._kind) {
      _Kind.number => _cmpNum(switch (field) {
        LotFilterField.score => lot.score?.toDouble(),
        _ => lot.tonnage,
      }, double.tryParse(value.replaceAll(',', '.'))),
      _Kind.date => _cmpDate(lot.date, DateTime.tryParse(value)),
      _Kind.text => _cmpText(switch (field) {
        LotFilterField.mine => lot.mineName,
        LotFilterField.depot => lot.depotName,
        _ => lot.plate,
      }),
      _Kind.statut => lot.validationStatus == value ? 0 : 1,
    };
    // Valeur absente (ex. score pas encore reçu) : seul « ≠ » la retient.
    if (cmp == null) return op == LotFilterOp.ne;
    return switch (op) {
      LotFilterOp.eq => cmp == 0,
      LotFilterOp.ne => cmp != 0,
      LotFilterOp.gt => cmp > 0,
      LotFilterOp.lt => cmp < 0,
      LotFilterOp.gte => cmp >= 0,
      LotFilterOp.lte => cmp <= 0,
    };
  }

  int? _cmpNum(double? a, double? b) =>
      a == null || b == null ? null : a.compareTo(b);

  int? _cmpDate(DateTime a, DateTime? b) =>
      b == null ? null : DateUtils.dateOnly(a).compareTo(DateUtils.dateOnly(b));

  int? _cmpText(String? a) {
    String n(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return a == null ? null : n(a).compareTo(n(value));
  }

  String get summary {
    final shown = field._kind == _Kind.statut
        ? _statuts[value] ?? value
        : value;
    return '${field.label} ${op.label} $shown';
  }
}

/// Ouvre la fenêtre de filtres ; retourne les critères ou `null` si fermée.
Future<List<LotFilterRule>?> showLotFilters(
  BuildContext context,
  List<LotFilterRule> initial,
) => showModalBottomSheet<List<LotFilterRule>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _LotFiltersSheet(initial),
);

class _Row {
  LotFilterField field;
  LotFilterOp op;
  String value;
  _Row(this.field, this.op, this.value);
}

class _LotFiltersSheet extends StatefulWidget {
  final List<LotFilterRule> initial;
  const _LotFiltersSheet(this.initial);

  @override
  State<_LotFiltersSheet> createState() => _LotFiltersSheetState();
}

class _LotFiltersSheetState extends State<_LotFiltersSheet> {
  late final List<_Row> _rows = [
    for (final r in widget.initial) _Row(r.field, r.op, r.value),
  ];

  List<LotFilterOp> _ops(LotFilterField f) =>
      f.ordered ? LotFilterOp.values : const [LotFilterOp.eq, LotFilterOp.ne];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Filtres', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Tous les critères doivent être respectés.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final row in _rows) _ruleRow(row),
            TextButton.icon(
              onPressed: () => setState(
                () => _rows.add(
                  _Row(LotFilterField.tonnage, LotFilterOp.gte, ''),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un critère'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, const []),
                    child: const Text('Réinitialiser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, [
                      for (final r in _rows)
                        if (r.value.isNotEmpty)
                          LotFilterRule(r.field, r.op, r.value),
                    ]),
                    child: const Text('Appliquer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleRow(_Row row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: DropdownButtonFormField<LotFilterField>(
            initialValue: row.field,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final f in LotFilterField.values)
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (f) => setState(() {
              if (f == null) return;
              row.field = f;
              row.value = '';
              if (!_ops(f).contains(row.op)) row.op = LotFilterOp.eq;
            }),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<LotFilterOp>(
            initialValue: row.op,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final o in _ops(row.field))
                DropdownMenuItem(value: o, child: Text(o.label)),
            ],
            onChanged: (o) => setState(() => row.op = o ?? row.op),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(flex: 5, child: _valueInput(row)),
        IconButton(
          tooltip: 'Retirer',
          onPressed: () => setState(() => _rows.remove(row)),
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );

  Widget _valueInput(_Row row) {
    switch (row.field._kind) {
      case _Kind.statut:
        return DropdownButtonFormField<String>(
          key: ValueKey('${row.field}-statut'),
          initialValue: row.value.isEmpty ? null : row.value,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            for (final e in _statuts.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => row.value = v ?? ''),
        );
      case _Kind.date:
        return OutlinedButton(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(row.value) ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(
                () => row.value = DateFormat('yyyy-MM-dd').format(picked),
              );
            }
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            row.value.isEmpty
                ? 'Choisir'
                : DateFormat('dd/MM/yyyy').format(DateTime.parse(row.value)),
            style: const TextStyle(fontSize: 12, color: AppColors.ink),
          ),
        );
      case _Kind.number:
      case _Kind.text:
        return TextFormField(
          key: ValueKey('${row.field}-text'),
          initialValue: row.value,
          keyboardType: row.field._kind == _Kind.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: const InputDecoration(isDense: true, hintText: 'Valeur'),
          onChanged: (v) => row.value = v.trim(),
        );
    }
  }
}
