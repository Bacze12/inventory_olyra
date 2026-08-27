import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../data/models/product.dart';
import '../products/product_provider.dart';
import 'label_print_service.dart';
import 'thermal_print_service.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  final TextEditingController _searchController = TextEditingController();
  final LabelPrintService _labelService = const LabelPrintService();
  final ThermalPrintService _thermalService = const ThermalPrintService();

  Product? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _printPdf(Product product) async {
    final messenger = ScaffoldMessenger.of(context);
    await _labelService.printLabel(product);
    messenger.showSnackBar(
      const SnackBar(content: Text('Diálogo de impresión cerrado')),
    );
  }

  Future<void> _printViaBluetooth(Product product) async {
    final messenger = ScaffoldMessenger.of(context);

    List<BluetoothInfo> devices;
    try {
      devices = await _thermalService.listDevices();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
      return;
    }

    if (!mounted) return;
    if (devices.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No hay impresoras Bluetooth vinculadas.\n'
            'Vincula una en Ajustes > Bluetooth del teléfono.',
          ),
        ),
      );
      return;
    }

    final device = await showModalBottomSheet<BluetoothInfo>(
      context: context,
      builder: (sheetContext) => _DevicePicker(devices: devices),
    );
    if (device == null) return;

    messenger.showSnackBar(
      const SnackBar(content: Text('Imprimiendo…')),
    );
    try {
      final ok = await _thermalService.printLabel(product, device.macAdress);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Etiqueta enviada a ${device.name}'
                : 'Error al enviar a la impresora',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Etiqueta / Impresión')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => provider.setQuery(value),
              decoration: const InputDecoration(
                hintText: 'Buscar producto…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: provider.products.isEmpty
                ? const _NoProducts()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: provider.products.length,
                    itemBuilder: (context, index) {
                      final product = provider.products[index];
                      final selected = _selected?.id == product.id;
                      final scheme = Theme.of(context).colorScheme;
                      return ListTile(
                        onTap: () => setState(() => _selected = product),
                        selected: selected,
                        selectedTileColor:
                            scheme.primaryContainer.withValues(alpha: 0.5),
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected ? scheme.primary : scheme.outline,
                        ),
                        title: Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(product.barcode, maxLines: 1),
                        trailing: Text(
                          '${product.quantity}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_selected != null) _buildLabelPanel(_selected!),
        ],
      ),
    );
  }

  Widget _buildLabelPanel(Product product) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 180,
                child: PdfPreview(
                  build: (format) async => _labelService.buildLabelPdf(product),
                  canChangeOrientation: false,
                  useActions: false,
                  maxPageWidth: 600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _printPdf(product),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Imprimir (PDF)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _printViaBluetooth(product),
                      icon: const Icon(Icons.bluetooth),
                      label: const Text('Bluetooth'),
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

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({required this.devices});

  final List<BluetoothInfo> devices;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Selecciona la impresora Bluetooth',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return ListTile(
                  leading: const Icon(Icons.bluetooth_connected),
                  title: Text(device.name),
                  subtitle: Text(device.macAdress),
                  onTap: () => Navigator.pop(context, device),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoProducts extends StatelessWidget {
  const _NoProducts();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.print_outlined, size: 64, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'Registra productos para imprimir sus etiquetas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}