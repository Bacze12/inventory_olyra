import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'shift_provider.dart';

/// Diálogo de apertura de turno: elige/crea la caja, el cajero, su PIN y el
/// fondo inicial. Valida el PIN del cajero (o crea el cajero si es nuevo).
class ShiftOpenDialog extends StatefulWidget {
  const ShiftOpenDialog({super.key});

  @override
  State<ShiftOpenDialog> createState() => _ShiftOpenDialogState();
}

class _ShiftOpenDialogState extends State<ShiftOpenDialog> {
  final TextEditingController _cashierController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _openingController = TextEditingController();

  late String _registerId;
  String? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    final shifts = context.read<ShiftProvider>();
    _registerId = shifts.registerId;
    if (shifts.cashiers.isNotEmpty) {
      _cashierController.text = shifts.cashiers.first.name;
    }
  }

  @override
  void dispose() {
    _cashierController.dispose();
    _pinController.dispose();
    _openingController.dispose();
    super.dispose();
  }

  Future<void> _newRegister() async {
    final shifts = context.read<ShiftProvider>();
    final name = await _askName(
      title: 'Nueva caja',
      hint: 'Ej: Caja 2',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    await shifts.addRegister(name.trim());
    if (mounted) {
      setState(() => _registerId = shifts.registerId);
    }
  }

  Future<String?> _askName({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _submit() async {
    final cashierName = _cashierController.text.trim();
    final pin = _pinController.text.trim();
    if (cashierName.isEmpty) {
      setState(() => _error = 'Escribe el nombre del cajero.');
      return;
    }
    if (pin.length != 4) {
      setState(() => _error = 'El PIN debe tener 4 dígitos.');
      return;
    }
    final opening = double.tryParse(
          _openingController.text.trim().replaceAll(',', '.'),
        ) ??
        0.0;
    if (opening < 0) {
      setState(() => _error = 'El fondo inicial no puede ser negativo.');
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    final shifts = context.read<ShiftProvider>();
    final error = await shifts.openShift(
      cashierName: cashierName,
      pin: pin,
      openingAmount: opening,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _working = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final shifts = context.watch<ShiftProvider>();
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Abrir turno de caja'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _registerId,
                decoration: const InputDecoration(
                  labelText: 'Caja',
                  helperText: 'La caja del turno se elige al abrir',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final register in shifts.registers)
                    DropdownMenuItem(
                      value: register.id,
                      child: Text(register.name),
                    ),
                ],
                onChanged: _working
                    ? null
                    : (value) {
                        if (value != null && value != _registerId) {
                          setState(() => _registerId = value);
                          shifts.selectRegister(value);
                          setState(() {});
                        }
                      },
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _working ? null : _newRegister,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nueva caja'),
                ),
              ),
              if (shifts.cashiers.isNotEmpty) ...[
                Text('Cajeros registrados', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final cashier in shifts.cashiers)
                      ActionChip(
                        label: Text(cashier.name),
                        onPressed: _working
                            ? null
                            : () => _cashierController.text = cashier.name,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _cashierController,
                enabled: !_working,
                decoration: const InputDecoration(
                  labelText: 'Cajero',
                  hintText: 'Nombre del cajero',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                enabled: !_working,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'PIN (4 dígitos)',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _openingController,
                enabled: !_working,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Fondo inicial (opcional)',
                  hintText: '0',
                  prefixText: r'$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _working ? null : _submit,
          icon: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: const Text('Abrir turno'),
        ),
      ],
    );
  }
}