import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/i18n/app_strings.dart';
import '../osa/osa_metrics_screen.dart';
import '../pro/pro_gate.dart';
import '../pro/pro_provider.dart';
import '../products/product_list_screen.dart';
import '../printer/printer_screen.dart';
import '../products/product_provider.dart';
import '../reports/report_screen.dart';
import '../scanner/scanner_screen.dart';
import '../settings/settings_screen.dart';

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
    });
  }

  Future<void> _push(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!context.mounted) return;
    context.read<ProductProvider>().load();
  }

  /// Abre un módulo exclusivo de PRO: sin licencia el usuario aterriza en el
  /// paywall y el módulo no llega a construirse.
  Future<void> _pushProOnly(
    BuildContext context,
    Future<bool> Function(BuildContext) gate,
    Widget screen,
  ) async {
    if (!await gate(context)) return;
    if (!context.mounted) return;
    await _push(context, screen);
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final languageCode = Localizations.localeOf(context).languageCode;
    String tr(String key) => AppStrings.translate(languageCode, key);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr(AppStrings.homeSettings),
            onPressed: () => _push(context, const SettingsScreen()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroSection(
            title: tr(AppStrings.homeHeroTitle),
            subtitle: tr(AppStrings.homeHeroSubtitle),
            scanLabel: tr(AppStrings.homeScanNow),
            onScan: () => _push(context, const ScannerScreen()),
          ),
          const SizedBox(height: 12),
          if (productProvider.lowStockCount > 0) ...[
            _LowStockBanner(
              message: AppStrings.interpolate(
                languageCode,
                AppStrings.homeLowStock,
                args: {'count': productProvider.lowStockCount},
              ),
              onTap: () => _push(context, const ProductListScreen()),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _MenuTile(
                  icon: Icons.inventory_2_outlined,
                  title: tr(AppStrings.homeProducts),
                  subtitle: tr(AppStrings.homeProductsSubtitle),
                  onTap: () => _push(context, const ProductListScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MenuTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: tr(AppStrings.homeReport),
                  subtitle: tr(AppStrings.homeReportSubtitle),
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
                  title: tr(AppStrings.homeLabel),
                  subtitle: tr(AppStrings.homeLabelSubtitle),
                  onTap: () => _push(context, const PrinterScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MenuTile(
                  icon: Icons.qr_code_scanner,
                  title: tr(AppStrings.homeScanner),
                  subtitle: tr(AppStrings.homeScannerSubtitle),
                  onTap: () => _push(context, const ScannerScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MenuTile(
                  icon: Icons.insights_outlined,
                  title: tr(AppStrings.homeOsa),
                  subtitle: tr(AppStrings.homeOsaSubtitle),
                  proOnly: true,
                  onTap: () => _pushProOnly(
                    context,
                    ProGate.allowOsaMetrics,
                    const OsaMetricsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.title,
    required this.subtitle,
    required this.scanLabel,
    required this.onScan,
  });

  final String title;
  final String subtitle;
  final String scanLabel;
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
            title,
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
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
            label: Text(scanLabel),
          ),
        ],
      ),
    );
  }
}

class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({
    required this.message,
    required this.onTap,
  });

  final String message;
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
                  message,
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
    this.proOnly = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// `true` en las funciones que el paywall vende como exclusivas de PRO. La
  /// tarjeta se sigue mostrando en la versión gratuita (para que el usuario
  /// sepa que existen), pero con el candado que anuncia el paywall.
  final bool proOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = proOnly && !context.watch<ProProvider>().esPro;

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
              Row(
                children: [
                  Icon(icon, size: 32, color: scheme.primary),
                  if (locked) ...[
                    const SizedBox(width: 8),
                    const _ProLockBadge(),
                  ],
                ],
              ),
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

/// Candado con el distintivo PRO que anticipa el paywall del menú.
class _ProLockBadge extends StatelessWidget {
  const _ProLockBadge();

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      key: const Key('menuProBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 12, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            AppStrings.translate(languageCode, AppStrings.proBadge),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}