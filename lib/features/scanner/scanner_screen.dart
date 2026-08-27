import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../products/product_form_screen.dart';
import 'scanner_provider.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.itf14,
      BarcodeFormat.itf2of5,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.unrestricted,
    torchEnabled: false,
    cameraResolution: const Size(1280, 720),
    autoZoom: true,
  );

  bool _torchOn = false;

  void _toggleTorch() {
    setState(() => _torchOn = !_torchOn);
    _scanner.toggleTorch();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _scanner.start();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _scanner.stop();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final codes = <String>[];
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        codes.add(raw);
      }
    }
    context.read<ScannerProvider>().handleScannedCodes(codes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            tapToFocus: true,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          const _ScanFrame(),
          _TopControls(
            scanner: _scanner,
            torchOn: _torchOn,
            onToggleTorch: _toggleTorch,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _BottomPanel(scanner: _scanner),
          ),
        ],
      ),
    );
  }
}

class _TopControls extends StatelessWidget {
  const _TopControls({
    required this.scanner,
    required this.torchOn,
    required this.onToggleTorch,
  });

  final MobileScannerController scanner;
  final bool torchOn;
  final VoidCallback onToggleTorch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: onToggleTorch,
              icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
              color: Colors.white,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
              ),
            ),
            Text(
              'Escaneo continuo',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              onPressed: scanner.switchCamera,
              icon: const Icon(Icons.cameraswitch_outlined),
              color: Colors.white,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.74,
          height: MediaQuery.of(context).size.height * 0.24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.75),
              width: 2.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.scanner});

  final MobileScannerController scanner;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OperationSelector(provider: provider),
            const SizedBox(height: 12),
            _ResultCard(
              provider: provider,
              onRegister: _registerMissing,
            ),
          ],
        ),
      ),
    );
  }

  void _registerMissing(BuildContext context) async {
    final provider = context.read<ScannerProvider>();
    final code = provider.lastBarcode;
    if (code.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(initialBarcode: code),
      ),
    );
    if (!context.mounted) return;
    if (created == true) {
      provider.clearResult();
      messenger.showSnackBar(
        const SnackBar(content: Text('Producto registrado')),
      );
    }
  }
}

class _OperationSelector extends StatelessWidget {
  const _OperationSelector({required this.provider});

  final ScannerProvider provider;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OperationButton(
            label: 'Entrada',
            operator: '+1',
            icon: Icons.add_circle_outline,
            selected: provider.operation == ScanOperation.entrada,
            color: Colors.green,
            onTap: () => provider.setOperation(ScanOperation.entrada),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _OperationButton(
            label: 'Salida',
            operator: '-1',
            icon: Icons.remove_circle_outline,
            selected: provider.operation == ScanOperation.salida,
            color: Colors.redAccent,
            onTap: () => provider.setOperation(ScanOperation.salida),
          ),
        ),
      ],
    );
  }
}

class _OperationButton extends StatelessWidget {
  const _OperationButton({
    required this.label,
    required this.operator,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String operator;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    operator,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.provider,
    required this.onRegister,
  });

  final ScannerProvider provider;
  final ValueChanged<BuildContext> onRegister;

  @override
  Widget build(BuildContext context) {
    final product = provider.lastProduct;
    final result = provider.lastResult;

    if (result == ScanResult.idle) {
      return const _HintCard();
    }

    final (Color accent, IconData icon, String title, String subtitle) =
        switch (result) {
      ScanResult.ok => (
          Colors.green,
          Icons.check_circle,
          product?.name ?? 'Producto',
          '${product?.quantity ?? 0} unidades  ·  ${provider.lastApplied > 0 ? '+' : ''}${provider.lastApplied}',
        ),
      ScanResult.lowStock => (
          Colors.redAccent,
          Icons.warning_amber_rounded,
          product?.name ?? 'Stock bajo',
          'STOCK BAJO · ${product?.quantity ?? 0} de ${product?.minStock ?? 0}',
        ),
      ScanResult.notFound => (
          Colors.deepOrange,
          Icons.help_outline,
          'Producto no encontrado',
          'Código ${provider.lastBarcode}',
        ),
      ScanResult.blocked => (
          Colors.amber,
          Icons.block,
          'Stock insuficiente',
          'No se puede aplicar una salida sin existencias.',
        ),
      ScanResult.error => (
          Colors.grey,
          Icons.error_outline,
          'Error de escaneo',
          'Intenta nuevamente.',
        ),
      ScanResult.idle => throw StateError('unreachable'),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(result),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                  if (provider.lastProduct != null)
                    Text(
                      formatDateTime(provider.lastScan.toIso8601String()),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (result == ScanResult.notFound)
              FilledButton.icon(
                onPressed: () => onRegister(context),
                icon: const Icon(Icons.add),
                label: const Text('Registrar'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.center_focus_strong,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10),
          Text(
            'Apunta la cámara al código de barras',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 64, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              'No se pudo acceder a la cámara.\n${error.errorCode.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}