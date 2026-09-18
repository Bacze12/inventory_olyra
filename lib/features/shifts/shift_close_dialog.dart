import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/pos_shift.dart';
import '../../data/repositories/shift_repository.dart';
import '../../l10n/app_localizations.dart';
import 'shift_provider.dart';

/// Diálogo de cierre de caja: pide el PIN del cajero del turno y el efectivo
/// contado. Al confirmar se cierra el turno y se devuelve un
/// [ShiftCloseResult] para mostrar el Ticket Z.
///
/// Muestra EN VIVO el cuadre: cada tecla del campo "Efectivo contado" recalcula
/// `diferencia = efectivoContado - efectivoEsperado` (con el esperado recargado
/// de las ventas en efectivo del turno), de modo que el cajero cuadre antes de
/// cerrar.
class ShiftCloseDialog extends StatefulWidget {
  const ShiftCloseDialog({super.key});

  @override
  State<ShiftCloseDialog> createState() => _ShiftCloseDialogState();
}

class _ShiftCloseDialogState extends State<ShiftCloseDialog> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _countedController = TextEditingController();

  /// Efectivo contado (parseado del campo, se actualiza con cada `onChanged`).
  double _efectivoContado = 0;

  /// Efectivo esperado: fondo inicial + ventas en efectivo del turno activo.
  double _expectedCash = 0;
  bool _expectedLoaded = false;

  String? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _loadExpected();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _countedController.dispose();
    super.dispose();
  }

  /// Recarga el esperado desde las ventas reales del turno (formato CLP).
  ///
  /// Pre-carga el campo "Efectivo contado" con ese saldo: así, si el cuadre
  /// está bien, el cajero solo confirma y la diferencia queda en $0,00 en vez
  /// de que un campo vacío (0) dispare "falta efectivo".
  Future<void> _loadExpected() async {
    final provider = context.read<ShiftProvider>();
    final shift = provider.activeShift;
    if (shift == null) return;
    try {
      final totals = await provider.currentTotals();
      final expected = ShiftRepository.expectedFor(shift, totals);
      if (!mounted) return;
      setState(() {
        _expectedCash = expected;
        _expectedLoaded = true;
        if (_countedController.text.trim().isEmpty) {
          _countedController.text = _amountText(expected);
          _efectivoContado = expected;
        }
      });
    } catch (_) {
      // Si falla la consulta, el esperado queda en 0; el cuadre fiscal
      // definitivo lo recalcula el provider al confirmar el cierre.
    }
  }

  /// Completar al saldo esperado (diferencia $0,00), para no dejar ningún
  /// importe pendiente por monos errores de tipeo.
  void _useExpected() {
    setState(() {
      _countedController.text = _amountText(_expectedCash);
      _efectivoContado = _expectedCash;
    });
  }

  static String _amountText(double value) =>
      value.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');

  void _onCountedChanged(String value) {
    final counted =
        double.tryParse(value.trim().replaceAll(',', '.')) ?? 0.0;
    setState(() => _efectivoContado = counted < 0 ? 0 : counted);
  }

  Future<void> _submit() async {
    final shifts = context.read<ShiftProvider>();
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      setState(() => _error = 'El PIN debe tener 4 dígitos.');
      return;
    }
    final counted =
        double.tryParse(_countedController.text.trim().replaceAll(',', '.')) ??
            0.0;
    if (counted < 0) {
      setState(() => _error = 'El efectivo contado no puede ser negativo.');
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    final result = await shifts.closeShift(pin: pin, counted: counted);
    if (!mounted) return;
    setState(() => _working = false);
    if (result == null) {
      setState(() => _error = 'PIN incorrecto. El turno sigue abierto.');
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final shifts = context.watch<ShiftProvider>();
    final shift = shifts.activeShift;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.shiftsCloseTitle),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shift != null) ...[
                _row(l10n.shiftsRegister, shifts.registerName),
                _row(l10n.shiftsCashier, _cashierName(shift)),
                _row(
                  l10n.shiftsOpenedAt,
                  _formatDateTime(shift.openedAt),
                ),
                _row(l10n.shiftsOpeningFund, formatMoney(shift.openingAmount)),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                enabled: !_working,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: l10n.shiftsPin,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _row(
                l10n.shiftsExpectedCash,
                _expectedLoaded ? formatMoney(_expectedCash) : l10n.shiftsExpectedPlaceholder,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _countedController,
                enabled: !_working,
                onChanged: _onCountedChanged,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.shiftsCountedCash,
                  prefixText: r'$ ',
                  border: OutlineInputBorder(),
                  helperText: l10n.shiftsCountedHelper,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _working ? null : _useExpected,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(l10n.shiftsUseExpected),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _differenceCard(scheme),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton.icon(
          onPressed: _working ? null : _submit,
          icon: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock),
          label: Text(l10n.shiftsCloseAction),
        ),
      ],
    );
  }

  /// Cuadre en vivo: `diferencia = efectivoContado - efectivoEsperado`.
  /// Cuando coinciden (o la caja está a $0/$0) muestra $0,00 en verde.
  Widget _differenceCard(ColorScheme scheme) {
    final diferencia = _efectivoContado - _expectedCash;
    final matches = diferencia.abs() < 0.009;
    final color = matches ? Colors.green.shade700 : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(AppLocalizations.of(context).shiftsDifference,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            formatMoney(diferencia),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _cashierName(PosShift shift) {
    final cashierId = shift.cashierId;
    if (cashierId == null) return '—';
    for (final cashier in context.read<ShiftProvider>().cashiers) {
      if (cashier.id == cashierId) return cashier.name;
    }
    return '—';
  }

  String _formatDateTime(String value) {
    final local = DateTime.parse(value).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}