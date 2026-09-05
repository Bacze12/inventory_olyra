import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/formatters.dart';
import '../../data/services/pairing_service.dart';

/// Pantalla de vinculación del lado de la PC.
///
/// Genera una sesión temporal (PIN de 6 dígitos + payload JSON), la muestra
/// como QR y como PIN legible, y permanece en "espera activa" mientras el
/// teléfono confirma el emparejamiento.
class DesktopPairingView extends StatefulWidget {
  const DesktopPairingView({super.key, this.service});

  final PairingService? service;

  @override
  State<DesktopPairingView> createState() => _DesktopPairingViewState();
}

class _DesktopPairingViewState extends State<DesktopPairingView> {
  PairingService? _service;
  PairingSession? _session;
  String? _qrPayload;
  PairingCredentials? _paired;

  int _generation = 0;
  bool _busy = true;

  Timer? _countdown;
  Timer? _poll;

  PairingService get _svc => _service!;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? context.read<PairingService>();
    _start();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _countdown?.cancel();
    _countdown = null;
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _start() async {
    _stopTimers();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _session = null;
      _qrPayload = null;
      _paired = null;
    });

    final session = await _svc.startSession();
    if (!mounted || _generation != generation) return;

    setState(() {
      _session = session;
      _qrPayload = _svc.encodePayload(session);
      _busy = false;
    });

    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkPairing());
    _checkPairing();
    _refreshServerHost(session, generation);
  }

  /// Incorpora la IP LAN de la PC al QR cuando se detecta (la detección de
  /// interfaces es I/O real, así que corre en segundo plano sin bloquear la
  /// pantalla en entornos sin red).
  Future<void> _refreshServerHost(PairingSession session, int generation) async {
    final host = await _svc.detectLanIpv4();
    if (!mounted ||
        _generation != generation ||
        host == null ||
        _session == null) {
      return;
    }
    final updated = PairingSession(
      tenantId: session.tenantId,
      pairCode: session.pairCode,
      expiresAt: session.expiresAt,
      serverHost: host,
      serverPort: PairingService.defaultSyncPort,
    );
    setState(() {
      _session = updated;
      _qrPayload = _svc.encodePayload(updated);
    });
  }

  Future<void> _checkPairing() async {
    final session = _session;
    if (session == null) return;
    final generation = _generation;

    final result = await _svc.checkPairing(session);
    if (!mounted || _generation != generation) return;

    if (result.expired) {
      _stopTimers();
      setState(() {});
    } else if (result.confirmed) {
      _stopTimers();
      setState(() => _paired = result.credentials);
    }
  }

  Future<void> _confirmManually() async {
    final session = _session;
    if (session == null || session.isExpired) return;
    final messenger = ScaffoldMessenger.of(context);

    await _svc.confirmManually(session);
    if (!mounted) return;
    final credentials = await _svc.credentials();
    if (!mounted) return;

    _stopTimers();
    setState(() {
      _paired = credentials;
      _session = null;
      _qrPayload = null;
    });
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Vinculación local completada. La tienda quedó autorizada.'),
      ),
    );
  }

  Future<void> _unlink() async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desvincular dispositivo?'),
        content: const Text(
          'Se eliminará la vinculación con la tienda de este dispositivo.',
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
    setState(() {
      _paired = null;
      _session = null;
      _qrPayload = null;
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('Dispositivo desvinculado.')),
    );
    _start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular con celular / PC')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_paired != null) {
      return _PairedPanel(
        credentials: _paired!,
        onRegenerate: () => _start(),
        onUnlink: _unlink,
        onDone: () => Navigator.of(context).maybePop(),
      );
    }
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final session = _session;
    if (session == null) {
      return _ExpiredPanel(onRegenerate: _start);
    }
    if (session.isExpired) {
      return _ExpiredPanel(onRegenerate: _start);
    }

    return _WaitingPanel(
      session: session,
      qrPayload: _qrPayload ?? '',
      manualConfirm: _confirmManually,
      onRegenerate: _start,
    );
  }
}

class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({
    required this.session,
    required this.qrPayload,
    required this.manualConfirm,
    required this.onRegenerate,
  });

  final PairingSession session;
  final String qrPayload;
  final VoidCallback manualConfirm;
  final VoidCallback onRegenerate;

  String get _remaining {
    final total = session.timeLeft.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(minutes)}:${two(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escanea el código QR desde el celular',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tienda: ${session.tenantId}',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: QrImageView(
                key: const ValueKey('pairing_qr'),
                data: qrPayload,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                'Si la cámara falla, escribe este PIN en el celular:',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                session.pairCode,
                key: const ValueKey('pairing_pin'),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 10,
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined, size: 16),
                  const SizedBox(width: 4),
                  Text('Expira en $_remaining'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          key: const ValueKey('pairing_status'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Esperando conexión del teléfono…',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Abre la app en el celular → "Vincular con PC/Celular" → '
          'escanea este código o escribe el PIN.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh),
                label: const Text('Generar nuevo código'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: manualConfirm,
                icon: const Icon(Icons.done_all),
                label: const Text('Confirmar manualmente'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Sin servidor de intercambio, la confirmación manual da por '
          'vinculado el dispositivo localmente después de guardar el PIN '
          'en el celular.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ExpiredPanel extends StatelessWidget {
  const _ExpiredPanel({required this.onRegenerate});

  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.timer_off_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          const Text(
            'El código expiró',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Los códigos de vinculación son temporales. '
            'Genera uno nuevo para continuar.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh),
            label: const Text('Generar nuevo código'),
          ),
        ],
      ),
    );
  }
}

class _PairedPanel extends StatelessWidget {
  const _PairedPanel({
    required this.credentials,
    required this.onRegenerate,
    required this.onUnlink,
    required this.onDone,
  });

  final PairingCredentials credentials;
  final VoidCallback onRegenerate;
  final VoidCallback onUnlink;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(Icons.check_circle, size: 72, color: Colors.green.shade600),
        const SizedBox(height: 12),
        const Text(
          'Dispositivo vinculado',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Ambos dispositivos quedaron autorizados para el catálogo e '
          'historial de la tienda.',
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
              _InfoRow(label: 'Tienda', value: credentials.tenantId),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Token',
                value: _maskToken(credentials.deviceToken),
              ),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Vinculado',
                value: formatDateTime(credentials.pairedAt),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onDone,
                icon: const Icon(Icons.check),
                label: const Text('Listo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.link),
                label: const Text('Vincular otro dispositivo'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onUnlink,
          icon: const Icon(Icons.link_off),
          label: const Text('Desvincular'),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
        ),
      ],
    );
  }

  String _maskToken(String token) {
    if (token.length <= 10) return token;
    return '${token.substring(0, 8)}…${token.substring(token.length - 4)}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
        ),
      ],
    );
  }
}