import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/settings_repository.dart';
import '../../views/pairing/desktop_pairing_view.dart';
import '../../views/pairing/mobile_scan_pairing_view.dart';
import '../products/product_list_screen.dart';
import '../printer/printer_screen.dart';
import '../products/product_provider.dart';
import '../reports/report_screen.dart';
import '../scanner/scanner_screen.dart';
import '../../services/update_service.dart';
import '../../views/pos/pos_desktop_view.dart';
import '../../views/sales/sales_history_view.dart';

bool _isDesktop() {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().load();
      UpdateService.checkForUpdates(
        context,
        context.read<SettingsRepository>(),
      );
    });
  }

  Future<void> _push(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!context.mounted) return;
    context.read<ProductProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroSection(
            onScan: () => _push(context, const ScannerScreen()),
          ),
          const SizedBox(height: 12),
          if (productProvider.lowStockCount > 0) ...[
            _LowStockBanner(
              count: productProvider.lowStockCount,
              onTap: () => _push(context, const ProductListScreen()),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          _MenuTile(
            icon: Icons.point_of_sale,
            title: 'Punto de venta',
            subtitle: 'Venta rápida en PC · F12 para cobrar',
            onTap: () => _push(context, const PosDesktopView()),
          ),
          const SizedBox(height: 12),
          _MenuTile(
            icon: Icons.receipt_long_outlined,
            title: 'Historial de ventas',
            subtitle: 'Ventas del POS · detalle y anulación',
            onTap: () => _push(context, const SalesHistoryView()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MenuTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Productos',
                  subtitle: 'Catálogo y stock',
                  onTap: () => _push(context, const ProductListScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MenuTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Reporte PDF',
                  subtitle: 'Exportar y guardar',
                  onTap: () => _push(context, const ReportScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MenuTile(
                  icon: Icons.print_outlined,
                  title: 'Imprimir etiqueta',
                  subtitle: 'Bluetooth / PDF',
                  onTap: () => _push(context, const PrinterScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MenuTile(
                  icon: Icons.qr_code_scanner,
                  title: 'Escáner',
                  subtitle: 'Entradas y salidas',
                  onTap: () => _push(context, const ScannerScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MenuTile(
            icon: Icons.devices,
            title: 'Vincular dispositivo',
            subtitle: 'Emparejar esta PC con un celular (QR / PIN)',
            onTap: () => _push(
              context,
              _isDesktop()
                  ? const DesktopPairingView()
                  : const MobileScanPairingView(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventario al instante',
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Escanea y actualiza existencias sin conexión.',
            style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onScan,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.onPrimary,
              foregroundColor: scheme.primary,
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear ahora'),
          ),
        ],
      ),
    );
  }
}

class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count producto(s) llegaron a su stock mínimo',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}