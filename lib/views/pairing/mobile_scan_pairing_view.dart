import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../data/services/pairing_service.dart';

enum _PairingMode { scan, pin }

/// Pantalla de vinculación del lado móvil.
///
/// Usa [MobileScanner] para leer el QR mostrado por la PC, o permite ingresar
/// el PIN de 6 dígitos como alternativa (junto con el código de tienda que se
/// muestra en la PC junto al QR).
class MobileScanPairingView extends StatefulWidget {
  const MobileScanPairingView({super.key, this.service});

  final PairingService? service;

  @override
  State<MobileScanPairingView> createState() => _MobileScanPairingViewState();
}

class _MobileScanPairingViewState extends State<MobileScanPairingView> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    torchEnabled: false,
    // Resolución 16:9 estándar (NUNCA 4:3 como 1280x960): evita
    // "Stream configuration failed" en el pipeline Camera2/CameraX de
    // Android cuando el sensor no soporta el par entrada/salida pedido.
    cameraResolution: const Size(1280, 720),
  );

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _tenantController = TextEditingController();
  final TextEditingController _serverIpController = TextEditingController();

  PairingService? _service;
  PairingCredentials? _paired;
  bool _loadingStatus = true;
  bool _busy = false;
  bool _handling = false;
  DateTime? _lastInvalid;
  _PairingMode _mode = _PairingMode.scan;

  PairingService get _svc => _service!;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? context.read<PairingService>();
    _loadStatus();
  }

  @override
  void dispose() {
    // Libera la cámara: se detiene el sensor antes de descartar el
    // controlador para no dejar sesiones de Camera2/CameraX colgadas.
    unawaited(_scanner.stop());
    unawaited(_scanner.dispose());
    _pinController.dispose();
    _tenantController.dispose();
    _serverIpController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final credentials = await _svc.credentials();
    if (!mounted) return;
    setState(() {
      _paired = credentials;
      _loadingStatus = false;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handling) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      _handlePayload(raw.trim());
      return;
    }
  }

  void _handlePayload(String raw) {
    final payload = _svc.parsePayload(raw);
    if (payload == null) {
      _warnInvalid(expired: false);
      return;
    }
    if (payload.isExpired) {
      _warnInvalid(expired: true);
      return;
    }
    _askToLink(payload);
  }

  void _warnInvalid({required bool expired}) {
    final now = DateTime.now();
    if (_lastInvalid != null && now.difference(_lastInvalid!) < const Duration(seconds: 2)) {
      return;
    }
    _lastInvalid = now;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          expired
              ? 'El código QR expiró. Genera uno nuevo en la PC.'
              : 'Código QR inválido. Escanea el QR de la PC.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _askToLink(PairPayload payload) async {
    _handling = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.devices),
        title: const Text('¿Vincular este dispositivo?'),
        content: Text(
          'Se asociará este celular a la tienda\n${payload.tenantId}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
    if (!mounted) {
      _handling = false;
      return;
    }
    if (confirmed != true) {
      _handling = false;
      return;
    }

    await _link(payload);
  }

  Future<void> _submitPin() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_pinController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa el PIN de 6 dígitos que muestra la PC.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);

    var tenantId = _tenantController.text.trim();
    final existing = await _svc.credentials();
    if ((tenantId.isEmpty || tenantId == 'STORE_') && existing != null) {
      tenantId = existing.tenantId;
    }
    if (tenantId.isEmpty || tenantId == 'STORE_') {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Ingresa el código de tienda que se muestra en la PC junto al QR '
            '(el PIN solo no identifica la tienda).',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // El PIN no transporta fecha de expiración: se asume vigente durante la
    // sesión típica. La validación estricta llega con un servidor de relay.
    final payload = PairPayload(
      tenantId: tenantId,
      pairCode: _pinController.text.trim(),
      expiresAt: DateTime.now().add(PairingService.defaultTtl),
    );

    final outcome = await _link(payload);
    if (outcome == PairingOutcome.ok) {
      final ip = _serverIpController.text.trim();
      if (ip.isNotEmpty) {
        await _svc.saveSyncServerUrl(
          'http://$ip:${PairingService.defaultSyncPort}',
        );
      }
    }
  }

  Future<PairingOutcome> _link(PairPayload payload) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);

    final outcome = await _svc.linkWithPayload(payload);
    if (!mounted) {
      _handling = false;
      return outcome;
    }

    _handling = false;
    switch (outcome) {
      case PairingOutcome.ok:
        final credentials = await _svc.credentials();
        if (!mounted) return outcome;
        setState(() {
          _paired = credentials;
          _busy = false;
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Dispositivo vinculado a la tienda.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case PairingOutcome.invalidPayload:
        setState(() => _busy = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Código inválido. Intenta nuevamente.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case PairingOutcome.expired:
        setState(() => _busy = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('El código expiró. Genera uno nuevo en la PC.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case PairingOutcome.sendFailed:
        setState(() => _busy = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo contactar el servidor de vinculación. '
              'Revisa la conexión e intenta de nuevo.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    return outcome;
  }

  Future<void> _unlink() async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desvincular este dispositivo?'),
        content: const Text(
          'Se eliminará la vinculación con esta tienda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    await _svc.unlink();
    if (!mounted) return;
    setState(() => _paired = null);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Dispositivo desvinculado.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Cambia a la pestaña "Ingresar PIN" sin quedarse en el error de cámara;
  /// la app nunca colapsa si el sensor falla.
  void _usePinFallback() {
    if (!mounted) return;
    unawaited(_scanner.stop());
    setState(() => _mode = _PairingMode.pin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular con PC / Celular')),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_paired != null) {
      return _LinkedPanel(
        credentials: _paired!,
        onUnlink: _unlink,
        onDone: () => Navigator.of(context).maybePop(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_PairingMode>(
            segments: const [
              ButtonSegment(
                value: _PairingMode.scan,
                icon: Icon(Icons.qr_code_scanner),
                label: Text('Escanear código'),
              ),
              ButtonSegment(
                value: _PairingMode.pin,
                icon: Icon(Icons.pin_outlined),
                label: Text('Ingresar PIN'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              final next = selection.first;
              if (next != _mode) {
                // Al salir del modo escáner se libera la cámara (evita
                // previews/sesiones colgadas en segundo plano).
                if (_mode == _PairingMode.scan) unawaited(_scanner.stop());
                setState(() => _mode = next);
              }
            },
          ),
          const SizedBox(height: 16),
          if (_mode == _PairingMode.scan)
            _buildScanner(context)
          else
            _buildPinForm(context),
          const SizedBox(height: 16),
          Text(
            'Debes escanear el QR que muestra la PC en "Vincular con celular" '
            'o escribir el PIN de 6 dígitos y el código de tienda (STORE_…) '
            'indicado junto al QR.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    return Container(
      height: 260,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: MobileScanner(
        controller: _scanner,
        onDetect: _onDetect,
        tapToFocus: true,
        errorBuilder: (context, error) => _ScannerUnavailable(
          error: error,
          onUsePin: _usePinFallback,
        ),
      ),
    );
  }

  Widget _buildPinForm(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _tenantController,
              decoration: const InputDecoration(
                labelText: 'Código de tienda',
                hintText: 'STORE_123',
                prefixIcon: Icon(Icons.storefront_outlined),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              decoration: const InputDecoration(
                labelText: 'PIN de 6 dígitos',
                hintText: '482910',
                prefixIcon: Icon(Icons.pin_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverIpController,
              decoration: const InputDecoration(
                labelText: 'IP de la PC (opcional)',
                hintText: '192.168.1.50',
                prefixIcon: Icon(Icons.lan_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _submitPin,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('Vincular dispositivo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable({required this.error, required this.onUsePin});

  final MobileScannerException error;
  final VoidCallback onUsePin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined, size: 48, color: scheme.error),
            const SizedBox(height: 8),
            const Text(
              'No se pudo iniciar la cámara.\n'
              'Puede estar en uso por otra app o no ser compatible.\n'
              'Vincula con el PIN de la PC.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              error.errorCode.name,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onUsePin,
              icon: const Icon(Icons.pin_outlined),
              label: const Text('Usar PIN de 6 dígitos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkedPanel extends StatelessWidget {
  const _LinkedPanel({
    required this.credentials,
    required this.onUnlink,
    required this.onDone,
  });

  final PairingCredentials credentials;
  final VoidCallback onUnlink;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Icon(Icons.check_circle, size: 72, color: Colors.green.shade600),
          const SizedBox(height: 12),
          const Text(
            'Dispositivo vinculado',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Este celular quedó autorizado para el catálogo e historial '
            'de la tienda ${credentials.tenantId}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tienda: ${credentials.tenantId}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Token: ${_maskToken(credentials.deviceToken)}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onDone,
            icon: const Icon(Icons.check),
            label: const Text('Listo'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onUnlink,
            icon: const Icon(Icons.link_off),
            label: const Text('Desvincular'),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
          ),
        ],
      ),
    );
  }

  String _maskToken(String token) {
    if (token.length <= 10) return token;
    return '${token.substring(0, 8)}…${token.substring(token.length - 4)}';
  }
}