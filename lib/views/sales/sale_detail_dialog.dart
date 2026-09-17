import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/sales_repository.dart';
import '../../features/sales/sales_provider.dart';

/// Abre el diálogo con el detalle del ticket de una venta.
///
/// Al cerrarse sin anularla devuelve `false`; si se anuló con éxito devuelve
/// `true` para que la vista origine recargue el historial.
Future<bool> showSaleDetailDialog(BuildContext context, Sale sale) async {
  final id = sale.id ?? -1;
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _SaleDetailDialog(saleId: id),
  );
  return result ?? false;
}

class _SaleDetailDialog extends StatelessWidget {
  const _SaleDetailDialog({required this.saleId});

  final int saleId;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<SalesRepository>();
    return FutureBuilder<Sale>(
      future: repository.byId(saleId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AlertDialog(
            title: const Text('Detalle de venta'),
            content: const Text('No se pudo cargar el detalle de la venta.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cerrar'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const AlertDialog(
            title: Text('Detalle de venta'),
            content: SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return _SaleDetailContent(sale: snapshot.data!);
      },
    );
  }
}

class _SaleDetailContent extends StatelessWidget {
  const _SaleDetailContent({required this.sale});

  final Sale sale;

  Future<void> _anular(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final salesProvider = context.read<SalesProvider>();
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular venta'),
        content: Text(
          'Se devolverá el stock de ${sale.items.map((i) => i.productName).toList().join(', ')} '
          'al inventario. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.undo),
            label: const Text('Anular venta'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final error = await salesProvider.anularVenta(sale);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error ?? 'Venta anulada · stock devuelto al inventario',
          ),
        ),
      );
    if (error == null) navigator.pop(true);
  }

  void _reimprimir(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Ticket enviado a la impresora (simulado).'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anulada = sale.status == SaleStatus.anulada;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text('Venta ${sale.folio}'),
          ),
          _StatusChip(status: sale.status),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  formatDateTime(sale.createdAt),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 16),
                Icon(
                  sale.paymentMethod == PaymentMethod.tarjeta
                      ? Icons.credit_card
                      : Icons.payments_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  sale.paymentMethod.label,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const Divider(height: 28),
            // SingleChildScrollView (no ListView) para evitar el error
            // "RenderShrinkWrappingViewport" dentro de AlertDialog.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in sale.items) ...[
                      _ItemRow(item: item),
                      const Divider(height: 12),
                    ],
                    if (sale.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Sin ítems registrados.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            _MoneyRow(label: 'Subtotal', value: sale.subtotal),
            if (sale.taxAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _MoneyRow(label: 'Impuesto', value: sale.taxAmount),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(sale.total),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (sale.paymentMethod == PaymentMethod.efectivo) ...[
              const SizedBox(height: 6),
              _MoneyRow(
                label: 'Recibido',
                value: sale.received ?? sale.total,
              ),
              const SizedBox(height: 4),
              _MoneyRow(
                label: 'Vuelto',
                value: sale.change,
                emphasize: true,
              ),
            ],
            if (anulada) ...[
              const SizedBox(height: 8),
              Text(
                'Venta anulada · el stock fue devuelto al inventario.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!anulada)
          OutlinedButton.icon(
            onPressed: () => _anular(context),
            icon: const Icon(Icons.undo),
            label: const Text('Anular venta'),
          ),
        if (!anulada)
          FilledButton.icon(
            onPressed: () => _reimprimir(context),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Reimprimir Ticket'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final SaleItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(item.subtotal),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${item.quantity} × ${formatMoney(item.unitPrice)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SaleStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anulada = status == SaleStatus.anulada;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: anulada ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: anulada ? scheme.onErrorContainer : scheme.onPrimaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final double value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
      color: emphasize ? scheme.primary : null,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
        Flexible(
          child: Text(
            formatMoney(value),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}