import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/cash.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/cash_repository.dart';
import '../../features/cash/cash_provider.dart';

/// Pide el fondo inicial y abre un turno. Devuelve `true` si quedó abierto.
Future<bool> showCashOpenDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _OpenShiftDialog(),
  );
  return ok == true;
}

/// Panel de caja: turno actual, desglose por medio de pago, movimientos
/// manuales y cierre con cuadre.
Future<void> showCashPanelDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _CashPanelDialog(),
  );
}

class _CashPanelDialog extends StatefulWidget {
  const _CashPanelDialog();

  @override
  State<_CashPanelDialog> createState() => _CashPanelDialogState();
}

class _CashPanelDialogState extends State<_CashPanelDialog> {
  List<PaymentBreakdown> _breakdown = const [];
  List<CashMovement> _movements = const [];
  ShiftAccounting? _accounting;
  bool _busy = true;
  String? _error;
  CashProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cash = context.read<CashProvider>();
      _provider = cash;
      cash.addListener(_onCashChanged);
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onCashChanged);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final cash = context.read<CashProvider>();
    if (!cash.isLoaded) await cash.load();
    await _reload();
  }

  void _onCashChanged() => _reload();

  Future<void> _reload() async {
    final cash = context.read<CashProvider>();
    final shift = cash.shift;
    if (!mounted) return;
    setState(() {
      _busy = shift != null;
      _error = null;
    });
    if (shift == null || shift.id == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      final repo = context.read<CashRepository>();
      final breakdown = await repo.paymentBreakdown(shift.id!);
      final movements = await repo.movements(shift.id!);
      final accounting = await repo.accounting(shift.id!);
      if (!mounted) return;
      setState(() {
        _breakdown = breakdown;
        _movements = movements;
        _accounting = accounting;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los datos del turno';
        _busy = false;
      });
    }
  }

  Future<void> _openShift() async {
    final ok = await showCashOpenDialog(context);
    if (ok) await _reload();
  }

  Future<void> _addMovement(CashMovementType type) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _MovementDialog(type: type),
    );
    if (ok == true) await _reload();
  }

  Future<void> _startClose() async {
    final accounting = _accounting;
    if (accounting == null) return;
    final declared = await showDialog<double>(
      context: context,
      builder: (_) => _CloseShiftDialog(expected: accounting.expectedAmount),
    );
    if (declared == null || !mounted) return;

    final result = await context.read<CashProvider>().closeShift(declared);
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    final closed = result.shift;
    if (closed == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _CloseResultDialog(shift: closed),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cash = context.watch<CashProvider>();
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.savings_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Caja / Turno')),
          if (cash.isOpen)
            _StatusChip(
              label: 'Abierto',
              background: Colors.green.shade100,
              foreground: Colors.green.shade900,
            )
          else if (cash.shift != null)
            _StatusChip(
              label: 'Cerrado',
              background: scheme.surfaceContainerHighest,
              foreground: scheme.onSurfaceVariant,
            ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: _busy && cash.shift == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cash.shift == null)
                      _buildClosedState(cash)
                    else ...[
                      _buildShiftInfo(cash),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: TextStyle(color: scheme.error, fontSize: 12),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 12),
                        _buildBreakdownSection(),
                        const SizedBox(height: 12),
                        _buildMovementsSection(cash.isOpen),
                      ],
                      if (cash.isOpen && _accounting != null) ...[
                        const SizedBox(height: 12),
                        _buildExpectedSection(),
                      ],
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        if (cash.isOpen) ...[
          TextButton.icon(
            onPressed: _busy ? null : () => _addMovement(CashMovementType.expense),
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Egreso'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _addMovement(CashMovementType.income),
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Ingreso'),
          ),
        ] else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: _openShift,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Abrir turno'),
          ),
        ],
        if (cash.isOpen)
          FilledButton.icon(
            onPressed: _accounting == null || _busy ? null : _startClose,
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Cerrar y cuadrar'),
          ),
        if (cash.isOpen)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Salir'),
          ),
      ],
    );
  }

  Widget _buildClosedState(CashProvider cash) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            cash.isLoaded ? 'No hay un turno de caja abierto' : 'Cargando…',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Para vender y cuadrar el efectivo debes abrir la caja.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftInfo(CashProvider cash) {
    final shift = cash.shift!;
    final scheme = Theme.of(context).colorScheme;
    final info = <(String, String)>[
      ('Apertura', formatDateTime(shift.openedAt)),
      ('Fondo inicial', formatMoney(shift.initialAmount)),
      if (!shift.isOpen && shift.closedAt != null)
        ('Cierre', formatDateTime(shift.closedAt!)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in info)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 13)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        if (!shift.isOpen) ...[
          const Divider(height: 20),
          _ResultRow(
            label: 'Efectivo esperado',
            value: formatMoney(shift.expectedAmount ?? 0),
          ),
          _ResultRow(
            label: 'Efectivo contado',
            value: formatMoney(shift.declaredAmount ?? 0),
          ),
          const SizedBox(height: 8),
          _DifferenceBadge(difference: shift.difference ?? 0),
        ],
      ],
    );
  }

  Widget _buildBreakdownSection() {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'Ventas del turno por medio de pago',
      child: Column(
        children: [
          for (final row in _breakdown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(_paymentIcon(row.method), size: 16,
                      color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(row.method.label, style: const TextStyle(fontSize: 13)),
                  ),
                  Text('${row.count}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 90,
                    child: Text(
                      formatMoney(row.total),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMovementsSection(bool canEdit) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'Movimientos de caja',
      child: _movements.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Sin movimientos manuales',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            )
          : Column(
              children: [
                for (final move in _movements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          move.isIncome
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          size: 16,
                          color: move.isIncome
                              ? Colors.green.shade700
                              : scheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                move.description.isEmpty
                                    ? (move.isIncome ? 'Ingreso' : 'Egreso')
                                    : move.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                formatDateTime(move.createdAt),
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${move.isIncome ? '+' : '-'}${formatMoney(move.amount)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: move.isIncome
                                ? Colors.green.shade700
                                : scheme.error,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildExpectedSection() {
    final acc = _accounting!;
    return _SectionCard(
      title: 'Cuadre esperado',
      child: Column(
        children: [
          _ResultRow(
            label: 'Fondo inicial',
            value: formatMoney(acc.expectedAmount - acc.cashSalesTotal -
                acc.incomeTotal + acc.expenseTotal),
          ),
          _ResultRow(label: '+ Ventas en efectivo', value: formatMoney(acc.cashSalesTotal)),
          _ResultRow(label: '+ Ingresos', value: formatMoney(acc.incomeTotal)),
          _ResultRow(label: '− Egresos', value: formatMoney(acc.expenseTotal)),
          const Divider(height: 16),
          _ResultRow(
            label: 'Efectivo esperado',
            value: formatMoney(acc.expectedAmount),
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

IconData _paymentIcon(PaymentMethod method) {
  return switch (method) {
    PaymentMethod.efectivo => Icons.payments_outlined,
    PaymentMethod.debito => Icons.credit_card,
    PaymentMethod.tarjeta => Icons.credit_card,
    PaymentMethod.transferencia => Icons.currency_exchange,
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.normal)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _DifferenceBadge extends StatelessWidget {
  const _DifferenceBadge({required this.difference});

  final double difference;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = difference > 0.005;
    final under = difference < -0.005;
    final (String label, Color bg, Color fg) = over
        ? ('Sobrante ${formatMoney(difference.abs())}',
            Colors.green.shade100, Colors.green.shade900)
        : under
            ? ('Faltante ${formatMoney(difference.abs())}',
                scheme.errorContainer, scheme.onErrorContainer)
            : ('Caja cuadrada', Colors.blue.shade100, Colors.blue.shade900);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(over
              ? Icons.trending_up
              : under
                  ? Icons.trending_down
                  : Icons.check_circle_outline,
              size: 18,
              color: fg),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CloseResultDialog extends StatelessWidget {
  const _CloseResultDialog({required this.shift});

  final CashShift shift;

  @override
  Widget build(BuildContext context) {
    final declared = shift.declaredAmount ?? 0;
    final expected = shift.expectedAmount ?? 0;
    final difference = shift.difference ?? 0;
    final title = difference.abs() <= 0.005
        ? 'Caja cuadrada'
        : difference > 0
            ? 'Sobrante detectado'
            : 'Faltante detectado';
    return AlertDialog(
      icon: Icon(
        difference.abs() <= 0.005
            ? Icons.check_circle_outline
            : difference > 0
                ? Icons.trending_up
                : Icons.trending_down,
        color: Theme.of(context).colorScheme.primary,
        size: 36,
      ),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ResultRow(label: 'Efectivo esperado', value: formatMoney(expected)),
          const SizedBox(height: 4),
          _ResultRow(label: 'Efectivo contado', value: formatMoney(declared)),
          const SizedBox(height: 12),
          _DifferenceBadge(difference: difference),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}

double? _parseMoney(String raw) {
  final cleaned = raw.trim().replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value < 0) return null;
  return double.parse(value.toStringAsFixed(2));
}

/// Apertura de caja: fondo inicial.
class _OpenShiftDialog extends StatefulWidget {
  const _OpenShiftDialog();

  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  final TextEditingController _controller = TextEditingController(text: '0');
  bool _confirming = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = _parseMoney(_controller.text);
    if (amount == null) return;
    setState(() => _confirming = true);
    final error = await context.read<CashProvider>().openShift(amount);
    if (!mounted) return;
    if (error != null) {
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Apertura de caja'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Registra el fondo inicial que dejas en el cajón antes de vender.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(12),
            ],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Fondo inicial',
              border: OutlineInputBorder(),
              isDense: true,
              prefixText: '\$ ',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _confirming ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              _confirming || _parseMoney(_controller.text) == null ? null : _confirm,
          child: const Text('Abrir caja'),
        ),
      ],
    );
  }
}

/// Movimiento manual (ingreso o egreso).
class _MovementDialog extends StatefulWidget {
  const _MovementDialog({required this.type});

  final CashMovementType type;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  late final TextEditingController _amount =
      TextEditingController();
  final TextEditingController _description = TextEditingController();
  bool _saving = false;

  bool get _isIncome => widget.type == CashMovementType.income;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = _parseMoney(_amount.text);
    if (amount == null) return;
    setState(() => _saving = true);
    final error = await context.read<CashProvider>().addMovement(
          widget.type,
          amount,
          _description.text.trim(),
        );
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_isIncome ? 'Registrar ingreso' : 'Registrar egreso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isIncome
                ? 'Dinero que ENTRA a la caja sin ser una venta.'
                : 'Dinero que SALE de la caja sin ser una venta.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(12),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Monto',
              border: const OutlineInputBorder(),
              isDense: true,
              prefixText: '\$ ',
              icon: Icon(
                _isIncome
                    ? Icons.add_circle_outline
                    : Icons.remove_circle_outline,
                color: _isIncome ? Colors.green.shade700 : scheme.error,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Ej. Pago de proveedor, cambio menor…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              _saving || _parseMoney(_amount.text) == null ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Cierre de caja: campo del efectivo contado.
class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog({required this.expected});

  final double expected;

  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.expected.toStringAsFixed(0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Cierre de caja'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Cuenta el dinero del cajón e ingresa lo que tienes en efectivo. '
            'El sistema compara contra lo esperado.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _ResultRow(
            label: 'Efectivo esperado',
            value: formatMoney(widget.expected),
            emphasize: true,
          ),
          const Divider(height: 20),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(12),
            ],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Efectivo contado',
              border: OutlineInputBorder(),
              isDense: true,
              prefixText: '\$ ',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _parseMoney(_controller.text) == null
              ? null
              : () => Navigator.of(context).pop(_parseMoney(_controller.text)),
          child: const Text('Cerrar y cuadrar'),
        ),
      ],
    );
  }
}