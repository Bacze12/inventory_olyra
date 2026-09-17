import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../features/shifts/shift_provider.dart';

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

    return AlertDialog(
      title: const Text('Ticket Z · Cierre de caja'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row('Caja', shifts.registerName),
              _row('Fecha', _dateTime(result.closedAt ?? shift.closedAt)),
              const Divider(height: 24),
              _amount('Fondo inicial', shift.openingAmount),
              _row('Efectivo ventas', formatMoney(result.totals.cashTotal)),
              _row('Tarjeta ventas', formatMoney(result.totals.cardTotal)),
              _amount('Total ventas', result.totals.total),
              const Divider(height: 24),
              _amount('Efectivo esperado', result.expected),
              _amount('Efectivo contado', result.counted),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Diferencia',
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
                    ? 'El cuadre coincide. Caja cerrada.'
                    : difference > 0
                        ? 'Sobra efectivo en caja.'
                        : 'Falta efectivo en caja.',
                style: TextStyle(color: diffColor),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Listo'),
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