import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/sale.dart';
import '../../features/sales/sales_provider.dart';
import 'sale_detail_dialog.dart';

/// Historial de ventas registradas por el POS.
///
/// Filtros rápidos por rango de fechas + buscador por folio, producto o
/// código de barras. En pantallas anchas se muestra una tabla con cabecera;
/// en pantallas angostas, tarjetas apiladas.
class SalesHistoryView extends StatefulWidget {
  const SalesHistoryView({super.key});

  @override
  State<SalesHistoryView> createState() => _SalesHistoryViewState();
}

class _SalesHistoryViewState extends State<SalesHistoryView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SalesProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openDetail(Sale sale) async {
    final provider = context.read<SalesProvider>();
    final annulled = await showSaleDetailDialog(context, sale);
    if (!mounted) return;
    if (annulled) await provider.load();
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<SalesProvider>().clearQuery();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Historial de ventas')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final range in SalesRange.values)
                  ChoiceChip(
                    label: Text(range.label),
                    selected: provider.range == range,
                    onSelected: (_) => provider.setRange(range),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                if (value.trim().isEmpty) {
                  provider.clearQuery();
                } else {
                  provider.setQuery(value);
                }
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por folio, producto o código…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Limpiar búsqueda',
                        onPressed: _clearSearch,
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ventas: ${provider.sales.length} · '
                    'Recaudado: ${formatMoney(provider.totalAmount)}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildContent(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SalesProvider provider) {
    if (provider.loading && provider.sales.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.sales.isEmpty) {
      return _CenterStatus(
        icon: Icons.cloud_off_outlined,
        title: provider.error!,
      );
    }
    if (provider.sales.isEmpty) {
      return const _CenterStatus(
        icon: Icons.receipt_long_outlined,
        title: 'Sin ventas en este rango',
      );
    }

    final sales = provider.sales;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return wide ? _buildTable(sales) : _buildCards(sales);
      },
    );
  }

  Widget _buildTable(List<Sale> sales) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TableHeader(),
          const SizedBox(height: 4),
          for (final sale in sales) _TableRow(sale: sale, onTap: _openDetail),
        ],
      ),
    );
  }

  Widget _buildCards(List<Sale> sales) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: sales.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final sale = sales[index];
        return _SaleCard(sale: sale, onTap: _openDetail);
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  static const _style = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text('Folio', style: _style.copyWith(color: color)),
          ),
          Expanded(
            child: Text('Fecha y hora', style: _style.copyWith(color: color)),
          ),
          SizedBox(
            width: 110,
            child: Text('Método', style: _style.copyWith(color: color)),
          ),
          SizedBox(
            width: 140,
            child: Text(
              'Total',
              textAlign: TextAlign.end,
              style: _style.copyWith(color: color),
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              'Estado',
              textAlign: TextAlign.center,
              style: _style.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.sale, required this.onTap});

  final Sale sale;
  final ValueChanged<Sale> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anulada = sale.status == SaleStatus.anulada;

    return InkWell(
      onTap: () => onTap(sale),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                sale.folio,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(formatDateTime(sale.createdAt)),
            ),
            SizedBox(
              width: 110,
              child: Row(
                children: [
                  Icon(
                    sale.paymentMethod == PaymentMethod.tarjeta
                        ? Icons.credit_card
                        : Icons.payments_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sale.paymentMethod.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                formatMoney(sale.total),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StatusChip(status: sale.status),
                  if (sale.stockWarning && !anulada) ...[
                    const SizedBox(height: 4),
                    const _StockWarningBadge(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                size: 18, color: anulada ? scheme.outline : scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale, required this.onTap});

  final Sale sale;
  final ValueChanged<Sale> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anulada = sale.status == SaleStatus.anulada;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(sale),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    sale.folio,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatDateTime(sale.createdAt),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
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
                  const Spacer(),
                  Text(
                    formatMoney(sale.total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _StatusChip(status: sale.status),
                  if (sale.stockWarning && !anulada) ...[
                    const SizedBox(width: 8),
                    const _StockWarningBadge(),
                  ],
                  const Spacer(),
                  Text(
                    'Ver detalle',
                    style: TextStyle(
                      color: anulada ? scheme.outline : scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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

/// Aviso de stock insuficiente para ventas sincronizadas desde otro
/// dispositivo: el descuento se aplicó pero el stock físico pudo verse corto.
class _StockWarningBadge extends StatelessWidget {
  const _StockWarningBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 12,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            'Stock insuficiente',
            style: TextStyle(
              color: scheme.onTertiaryContainer,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterStatus extends StatelessWidget {
  const _CenterStatus({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}