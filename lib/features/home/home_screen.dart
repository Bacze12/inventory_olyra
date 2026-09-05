import 'dart:async';
import 'dart:io' show InternetAddress, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/pairing_service.dart';
import '../../data/services/sync_service.dart';
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
      _bootstrapSyncServer(context);
    });
  }

  /// En la PC vinculada levanta el servidor local (Shelf) para que el
  /// teléfono pueda sincronizar el catálogo y las ventas por Wi-Fi.
  Future<void> _bootstrapSyncServer(BuildContext context) async {
    if (!_isDesktop()) return;
    final pairing = context.read<PairingService>();
    final products = context.read<ProductRepository>();
    final sales = context.read<SalesRepository>();
    if (!await pairing.isPaired) return;
    final credentials = await pairing.credentials();

    final server = SyncServer(
      products: products,
      sales: sales,
      tenantId: credentials?.tenantId,
    );
    // 0.0.0.0: escucha en TODAS las interfaces para aceptar el celular de la
    // LAN (nunca loopback, que rechazaría peticiones de otros dispositivos).
    if (!await server.start(bindAddress: InternetAddress.anyIPv4)) {
      debugPrint('SyncServer: puerto ${SyncServer.defaultPort} ocupado.');
      return;
    }
    SyncServer.appServer = server;

    // Guarda la IP local para que el teléfono vinculado la use sin mDNS.
    final ip = await pairing.detectLanIpv4();
    if (ip != null) {
      await pairing.saveSyncServerUrl(
        'http://$ip:${SyncServer.defaultPort}',
      );
    }
  }

  Future<void> _syncNow(BuildContext context) async {
    final syncService = context.read<SyncService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SyncProgressDialog(),
    );

    final result = await syncService.syncNow();
    if (!context.mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(result.describe())),
    );
  }

  Future<void> _runDiagnostics(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _DiagnosticsDialog(),
    );
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
          if (_isDesktop()) ...[
            const _ServerStatusCard(),
            const SizedBox(height: 12),
          ],
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
          if (!_isDesktop()) ...[
            const SizedBox(height: 12),
            _MenuTile(
              icon: Icons.wifi_tethering,
              title: 'Sincronizar con PC',
              subtitle: 'Bajar catálogo y subir ventas (Wi-Fi)',
              onTap: () => _syncNow(context),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _runDiagnostics(context),
                icon: const Icon(Icons.healing, size: 18),
                label: const Text('Probar conexión (diagnóstico)'),
              ),
            ),
          ],
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

class _SyncProgressDialog extends StatelessWidget {
  const _SyncProgressDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text('Sincronizando con la PC…'),
          ),
        ],
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

/// Indicador del servidor local (Shelf) de la PC.
///
/// Verde/activo: "Servidor Sync Activo - http://IP:8080" con copia de la IP;
/// gris/inactivo: "Servidor Inactivo (Dispositivo no vinculado)".
class _ServerStatusCard extends StatefulWidget {
  const _ServerStatusCard();

  @override
  State<_ServerStatusCard> createState() => _ServerStatusCardState();
}

class _ServerStatusCardState extends State<_ServerStatusCard> {
  bool _active = false;
  String? _serverUrl;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _update();
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _update());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _update() async {
    final pairing = context.read<PairingService>();
    final url = await pairing.syncServerUrl();
    if (!mounted) return;
    setState(() {
      _active = SyncServer.appServer != null &&
          url != null &&
          url.isNotEmpty;
      _serverUrl = url;
    });
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    final ip = Uri.tryParse(_serverUrl ?? '')?.host;
    if (ip == null || ip.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: ip));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('IP copiada al portapapeles'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Diálogo de diagnóstico: regla de firewall y URL de prueba del health
  /// check para verificar desde el navegador del celular.
  Future<void> _showConnectionHelp() async {
    final ip = Uri.tryParse(_serverUrl ?? '')?.host ?? '';
    final healthUrl = ip.isEmpty
        ? ''
        : 'http://$ip:${SyncServer.defaultPort}/api/v1/sync/health';

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ayuda de conexión Wi-Fi'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Si el celular no encuentra la PC:'),
              const SizedBox(height: 8),
              const Text('• Verifica que ambos estén en la MISMA red Wi-Fi.'),
              const Text(
                '• Abre el puerto 8080 en el Firewall de Windows '
                '(ejecuta en PowerShell como administrador):',
              ),
              const SizedBox(height: 8),
              _CopyableCode(
                text: SyncServer.firewallRule,
                label: 'Copiar regla de firewall',
              ),
              const SizedBox(height: 16),
              const Text(
                '• Prueba la PC desde el navegador del celular con el health '
                'check:',
              ),
              const SizedBox(height: 8),
              if (healthUrl.isNotEmpty)
                _CopyableCode(text: healthUrl, label: 'Copiar URL de prueba'),
              const SizedBox(height: 16),
              const Text(
                'Si responde {"status":"ok"} con el mismo tenant_id, la PC '
                'es alcanzable y el sync funcionará.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background = _active
        ? const Color(0xFFE4F4E6)
        : scheme.surfaceContainerHighest;
    final Color foreground = _active
        ? const Color(0xFF1B5E20)
        : scheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              _active ? Icons.check_circle : Icons.cloud_off,
              size: 22,
              color: foreground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _active
                        ? 'Servidor Sync Activo'
                        : 'Servidor Inactivo (Dispositivo no vinculado)',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_active) ...[
                    const SizedBox(height: 2),
                    Text(
                      _serverUrl ?? '',
                      key: const ValueKey('server_status_url'),
                      style: TextStyle(color: foreground, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (_active)
              IconButton(
                tooltip: 'Copiar IP',
                icon: const Icon(Icons.copy_rounded, size: 20),
                color: foreground,
                onPressed: _copy,
              ),
            if (_active)
              IconButton(
                tooltip: 'Ayuda de conexión',
                icon: const Icon(Icons.help_outline, size: 20),
                color: foreground,
                onPressed: _showConnectionHelp,
              ),
          ],
        ),
      ),
    );
  }
}

/// Código o URL con botón para copiarlo (técnica de diagnóstico).
class _CopyableCode extends StatelessWidget {
  const _CopyableCode({required this.text, required this.label});

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: text));
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(label),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo que ejecuta [SyncService.diagnoseConnection] y muestra el resultado
/// en pantalla (URL, TCP, HTTP) para diagnosticar sin consola.
class _DiagnosticsDialog extends StatefulWidget {
  const _DiagnosticsDialog();

  @override
  State<_DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<_DiagnosticsDialog> {
  String? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final syncService = context.read<SyncService>();
    try {
      final report = await syncService.diagnoseConnection();
      if (!mounted) return;
      setState(() => _report = report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo ejecutar el diagnóstico: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _error ?? _report;
    return AlertDialog(
      title: const Text('Diagnóstico de conexión'),
      content: SizedBox(
        width: double.maxFinite,
        child: text == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _CopyableCode(text: text, label: 'Copiar diagnóstico'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}