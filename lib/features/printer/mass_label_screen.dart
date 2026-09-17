import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/product.dart';
import '../products/product_provider.dart';
import 'label_widgets.dart';
import 'mass_label_print_service.dart';

/// Selección de productos (y copias por producto) para impresión masiva de
/// etiquetas térmicas en la impresora predeterminada de Windows.
class MassLabelScreen extends StatefulWidget {
  const MassLabelScreen({super.key});

  @override
  State<MassLabelScreen> createState() => _MassLabelScreenState();
}

class _MassLabelScreenState extends State<MassLabelScreen> {
  final MassLabelPrintService _service = const MassLabelPrintService();
  final Set<int> _selected = {};
  final Map<int, int> _copies = {};
  ThermalLabelSize _size = ThermalLabelSize.label58x40;
  bool _printing = false;
  bool _all = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ProductProvider>();
      provider.setQuery('');
      provider.load();
    });
  }

  List<Product> get _products {
    final provider = context.read<ProductProvider>();
    return provider.products;
  }

  int get _totalCopies {
    var total = 0;
    for (final product in _products) {
      if (_selected.contains(product.id)) {
        total += _copies[product.id] ?? 1;
      }
    }
    return total;
  }

  void _toggleAll() {
    final products = _products;
    setState(() {
      _all = !_all;
      if (_all) {
        for (final product in products) {
          _selected.add(product.id!);
          _copies.putIfAbsent(product.id!, () => 1);
        }
      } else {
        _selected.clear();
      }
    });
  }

  void _setCopies(Product product, int copies) {
    setState(() => _copies[product.id!] = copies < 0 ? 0 : (copies > 999 ? 999 : copies));
  }

  Future<void> _print() async {
    final items = _products
        .where((p) => _selected.contains(p.id))
        .map((p) => MassLabelItem(product: p, copies: _copies[p.id] ?? 1))
        .toList();

    final messenger = ScaffoldMessenger.of(context);
    if (items.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un producto')),
      );
      return;
    }
    if (_service.totalLabels(items) == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Indica al menos una copia por producto')),
      );
      return;
    }

    setState(() => _printing = true);
    try {
      final ok = await _service.printLabels(items, _size);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Enviadas ${_service.totalLabels(items)} etiquetas a la impresora'
                : 'La impresión fue cancelada',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Error de impresión: $error')));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _savePdf() async {
    final items = _products
        .where((p) => _selected.contains(p.id))
        .map((p) => MassLabelItem(product: p, copies: _copies[p.id] ?? 1))
        .toList();
    final messenger = ScaffoldMessenger.of(context);
    if (items.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un producto')),
      );
      return;
    }
    try {
      await _service.savePdf(items, _size);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Error al guardar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Etiquetas masivas'),
        actions: [
          IconButton(
            icon: Icon(_all ? Icons.deselect : Icons.select_all),
            tooltip: _all ? 'Quitar selección' : 'Seleccionar todo',
            onPressed: products.isEmpty ? null : _toggleAll,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text('Tamaño etiqueta:', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                DropdownButton<ThermalLabelSize>(
                  value: _size,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final size in ThermalLabelSize.values)
                      DropdownMenuItem(
                        value: size,
                        child: Text(size.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _size = value);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: products.isEmpty
                ? const _EmptyCatalog()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final isSelected = _selected.contains(product.id);
                      final copies = _copies[product.id] ?? 1;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        child: ListTile(
                          onTap: () => setState(() {
                            if (isSelected) {
                              _selected.remove(product.id);
                            } else {
                              _selected.add(product.id!);
                              _copies.putIfAbsent(product.id!, () => 1);
                            }
                          }),
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(product.id!);
                                _copies.putIfAbsent(product.id!, () => 1);
                              } else {
                                _selected.remove(product.id);
                              }
                            }),
                          ),
                          title: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(product.barcode, maxLines: 1),
                          trailing: _CopiesStepper(
                            enabled: isSelected,
                            copies: copies,
                            onChanged: (c) => _setCopies(product, c),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _buildFooter(scheme),
        ],
      ),
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    final count = _selected.length;
    final labels = _totalCopies;
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count producto${count == 1 ? '' : 's'} · '
                      '$labels etiqueta${labels == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Text('Impresora predeterminada de Windows',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _printing ? null : _savePdf,
                icon: const Icon(Icons.save_alt),
                label: const Text('PDF'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _printing ? null : _print,
                icon: _printing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined),
                label: const Text('Imprimir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopiesStepper extends StatelessWidget {
  const _CopiesStepper({
    required this.enabled,
    required this.copies,
    required this.onChanged,
  });

  final bool enabled;
  final int copies;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = enabled ? scheme.primary : scheme.outlineVariant;
    final onColor = enabled ? scheme.onPrimary : scheme.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: color,
          onPressed: enabled ? () => onChanged(copies - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Menos copias',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: enabled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$copies',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: enabled ? scheme.onPrimaryContainer : onColor,
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: color,
          onPressed: enabled ? () => onChanged(copies + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Más copias',
        ),
      ],
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_off_outlined, size: 64, color: scheme.outline),
            const SizedBox(height: 12),
            const Text('Registra productos para imprimir sus etiquetas.'),
          ],
        ),
      ),
    );
  }
}