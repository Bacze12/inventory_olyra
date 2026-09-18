import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../features/shifts/shift_provider.dart';
import '../../l10n/app_localizations.dart';

/// Ticket Z: el comprobante/cuadre que se muestra al cerrar la caja.
class TicketZDialog extends StatelessWidget {
  const TicketZDialog({super.key, required this.result});

  final ShiftCloseResult result;

  @override
  Widget build(BuildContext context) {
    final shifts = context.watch<ShiftProvider>();
    final shift = result.shift;
    final scheme = Theme.of(context).colorScheme;
    final difference = result.difference;
    final matches = (difference.abs() < 0.009);
    final diffColor = matches ? Colors.green.shade700 : scheme.error;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.shiftsTicketTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row(l10n.shiftsRegister, shifts.registerName),
              _row(l10n.shiftsDate, _dateTime(result.closedAt ?? shift.closedAt)),
              const Divider(height: 24),
              _amount(l10n.shiftsOpeningFund, shift.openingAmount),
              _row(l10n.shiftsCashSales, formatMoney(result.totals.cashTotal)),
              _row(l10n.shiftsCardSales, formatMoney(result.totals.cardTotal)),
              _amount(l10n.shiftsTotalSales, result.totals.total),
              const Divider(height: 24),
              _amount(l10n.shiftsExpectedCash, result.expected),
              _amount(l10n.shiftsCountedLabel, result.counted),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.shiftsDifference,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    formatMoney(difference),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: diffColor,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                matches
                    ? l10n.shiftsRegMatch
                    : difference > 0
                        ? l10n.shiftsRegOver
                        : l10n.shiftsRegShort,
                style: TextStyle(color: diffColor),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonDone),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _amount(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            formatMoney(value),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _dateTime(String? value) {
    if (value == null) return '—';
    try {
      final local = DateTime.parse(value).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(local.day)}/${two(local.month)}/${local.year} '
          '${two(local.hour)}:${two(local.minute)}';
    } catch (_) {
      return '—';
    }
  }
}