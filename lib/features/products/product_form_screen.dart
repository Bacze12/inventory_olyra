import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/product.dart';
import '../scanner/barcode_capture_screen.dart';
import 'product_provider.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    this.product,
    this.initialBarcode,
  });

  final Product? product;
  final String? initialBarcode;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _quantityController;
  late final TextEditingController _minStockController;
  late final TextEditingController _priceController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product?.name ?? '');
    _barcodeController = TextEditingController(
      text: widget.initialBarcode ?? product?.barcode ?? '',
    );
    _quantityController = TextEditingController(
      text: product?.quantity.toString() ?? '0',
    );
    _minStockController = TextEditingController(
      text: product?.minStock.toString() ?? '0',
    );
    _priceController = TextEditingController(
      text: product?.price.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _quantityController.dispose();
    _minStockController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.product != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar producto' : 'Nuevo producto'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _nameField(),
              const SizedBox(height: 16),
              _barcodeField(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _numberField(
                    controller: _quantityController,
                    label: 'Cantidad actual',
                    icon: Icons.inventory_2_outlined,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField(
                    controller: _minStockController,
                    label: 'Stock mínimo',
                    icon: Icons.low_priority,
                  )),
                ],
              ),
              const SizedBox(height: 16),
              _priceField(),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isEditing ? 'Guardar cambios' : 'Registrar producto'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameField() => TextFormField(
        controller: _nameController,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          hintText: 'Ej. Agua mineral 500 ml',
          prefixIcon: Icon(Icons.sell_outlined),
        ),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Ingresa el nombre' : null,
      );

  Widget _barcodeField() => TextFormField(
        controller: _barcodeController,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Código de barras',
          hintText: 'Escanea o escribe el código',
          prefixIcon: const Icon(Icons.qr_code_2),
          suffixIcon: IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Escanear código',
            onPressed: _scanBarcode,
          ),
        ),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Ingresa el código de barras' : null,
      );

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
        validator: (value) {
          final parsed = int.tryParse(value ?? '');
          if (parsed == null || parsed < 0) {
            return 'Número inválido';
          }
          return null;
        },
      );

  Widget _priceField() => TextFormField(
        controller: _priceController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}([.,]\d{0,2})?')),
        ],
        decoration: const InputDecoration(
          labelText: 'Precio',
          hintText: '0.00',
          prefixIcon: Icon(Icons.attach_money_outlined),
        ),
        validator: (value) {
          final parsed = _parsePrice(value);
          if (parsed == null || parsed < 0) return 'Precio inválido';
          return null;
        },
      );

  double? _parsePrice(String? value) {
    if (value == null || value.trim().isEmpty) return 0.0;
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  Future<void> _scanBarcode() async {
    final messenger = ScaffoldMessenger.of(context);
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeCaptureScreen()),
    );
    if (!mounted) return;
    if (code == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Escaneo cancelado')));
      return;
    }
    _barcodeController.text = code;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ProductProvider>();

    setState(() => _saving = true);
    final base = widget.product;
    final now = nowIso();
    final draft = Product(
      id: base?.id,
      name: _nameController.text.trim(),
      barcode: normalizeBarcode(_barcodeController.text),
      quantity: int.tryParse(_quantityController.text) ?? 0,
      minStock: int.tryParse(_minStockController.text) ?? 0,
      price: _parsePrice(_priceController.text) ?? 0.0,
      createdAt: base?.createdAt ?? now,
      updatedAt: now,
    );

    final error = await provider.save(draft);
    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop(true);
  }
}