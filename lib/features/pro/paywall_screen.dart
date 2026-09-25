import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/i18n/app_strings.dart';
import 'billing.dart';
import 'pro_provider.dart';

/// Motivo por el que se abrió el paywall, para adaptar el encabezado.
enum PaywallTrigger {
  /// El usuario alcanzó el límite de productos de la versión gratuita.
  productLimit,

  /// El usuario entró por su cuenta desde Ajustes.
  settings,
}

/// Abre el paywall y devuelve `true` si el usuario terminó con licencia PRO.
Future<bool> showPaywall(
  BuildContext context, {
  PaywallTrigger trigger = PaywallTrigger.settings,
}) async {
  final upgraded = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => PaywallScreen(trigger: trigger)),
  );
  return upgraded ?? false;
}

/// Fila de la tabla comparativa: una función y lo que ofrece cada plan.
class _PlanFeature {
  const _PlanFeature({
    required this.titleKey,
    required this.freeKey,
    required this.proKey,
    required this.icon,
    this.highlight = false,
  });

  final String titleKey;
  final String freeKey;
  final String proKey;
  final IconData icon;

  /// `true` en las funciones que la versión gratuita no puede entregar: son el
  /// argumento de venta y se destacan con el rayo de PRO.
  final bool highlight;
}

typedef _Tr = String Function(String key);
typedef _Fill = String Function(String key, {Map<String, Object> args});

const List<_PlanFeature> _features = [
  _PlanFeature(
    titleKey: AppStrings.paywallFeatureProducts,
    freeKey: AppStrings.paywallValueUpTo,
    proKey: AppStrings.paywallValueUnlimited,
    icon: Icons.inventory_2_outlined,
    highlight: true,
  ),
  _PlanFeature(
    titleKey: AppStrings.paywallFeatureScanner,
    freeKey: AppStrings.paywallValueIncluded,
    proKey: AppStrings.paywallValueIncluded,
    icon: Icons.qr_code_scanner_outlined,
  ),
  _PlanFeature(
    titleKey: AppStrings.paywallFeatureLowStock,
    freeKey: AppStrings.paywallValueIncluded,
    proKey: AppStrings.paywallValueIncluded,
    icon: Icons.notifications_active_outlined,
  ),
  _PlanFeature(
    titleKey: AppStrings.paywallFeatureOsa,
    freeKey: AppStrings.paywallValueLocked,
    proKey: AppStrings.paywallValueAdvanced,
    icon: Icons.insights_outlined,
    highlight: true,
  ),
  _PlanFeature(
    titleKey: AppStrings.paywallFeaturePdf,
    freeKey: AppStrings.paywallValueLocked,
    proKey: AppStrings.paywallValueComplete,
    icon: Icons.picture_as_pdf_outlined,
    highlight: true,
  ),
];

/// Pantalla de venta de la suscripción BodegaFlow PRO.
///
/// Compara Gratis vs PRO y gatilla el flujo de pago oficial de Google Play con
/// el producto `bodegaflow_pro_monthly`.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.trigger = PaywallTrigger.settings});

  final PaywallTrigger trigger;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    // El precio se pide al abrir la pantalla, no al arrancar la app: un usuario
    // que no va a comprar no debe pagar una llamada de red en cada inicio.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProProvider>().loadOffers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pro = context.watch<ProProvider>();
    final languageCode = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;

    String tr(String key) => AppStrings.translate(languageCode, key);
    String fill(String key, {Map<String, Object> args = const {}}) =>
        AppStrings.interpolate(languageCode, key, args: args);

    return Scaffold(
      appBar: AppBar(title: Text(tr(AppStrings.paywallTitle))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Header(
              headline: tr(AppStrings.paywallHeadline),
              subtitle: tr(AppStrings.paywallSubtitle),
            ),
            const SizedBox(height: 20),
            if (pro.esPro)
              _ProActiveBanner(
                text: tr(AppStrings.paywallAlreadyPro),
                detail: tr(AppStrings.paywallFreeUsagePro),
              )
            else ...[
              _UsageCard(
                text: fill(
                  AppStrings.paywallFreeUsage,
                  args: {
                    'count': pro.remainingFreeSlots ?? 0,
                    'limit': AppConstants.freeProductLimit,
                  },
                ),
                used: pro.productCount,
                limit: AppConstants.freeProductLimit,
                blocked: widget.trigger == PaywallTrigger.productLimit,
                blockedText: fill(
                  AppStrings.paywallLimitReached,
                  args: {'limit': AppConstants.freeProductLimit},
                ),
              ),
              const SizedBox(height: 20),
              _ComparisonTable(features: _features, tr: tr, fill: fill),
              const SizedBox(height: 20),
              _PriceBlock(
                offer: pro.offers.isEmpty ? null : pro.offers.first,
                loading: pro.loadingOffers,
                loadingText: tr(AppStrings.paywallPriceLoading),
                unavailableText: tr(AppStrings.paywallPriceUnavailable),
                planName: tr(AppStrings.paywallTitle),
              ),
            ],
            const SizedBox(height: 8),
            _Notice(notice: pro.notice, tr: tr),
            const SizedBox(height: 8),
            _ProActions(
              pro: pro,
              onBuy: () => pro.purchasePro(),
              onRestore: () => pro.restorePurchases(),
            ),
            const SizedBox(height: 12),
            Text(
              tr(AppStrings.paywallLegal),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botonera del paywall. Con licencia PRO activa queda solo "Continuar", que
/// cierra la pantalla devolviendo `true` para que el flujo que la abrió siga.
class _ProActions extends StatelessWidget {
  const _ProActions({
    required this.pro,
    required this.onBuy,
    required this.onRestore,
  });

  final ProProvider pro;
  final VoidCallback onBuy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    String tr(String key) => AppStrings.translate(languageCode, key);

    if (pro.esPro) {
      return FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(tr(AppStrings.paywallClose)),
      );
    }

    return Column(
      children: [
        FilledButton.icon(
          onPressed: pro.busy ? null : onBuy,
          icon: pro.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open_outlined),
          label: Text(tr(AppStrings.paywallBuy)),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: pro.busy ? null : onRestore,
          icon: const Icon(Icons.restore_outlined, size: 18),
          label: Text(tr(AppStrings.paywallRestore)),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.headline, required this.subtitle});

  final String headline;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.workspace_premium, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 12),
        Text(
          headline,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
        ),
      ],
    );
  }
}

class _ProActiveBanner extends StatelessWidget {
  const _ProActiveBanner({required this.text, required this.detail});

  final String text;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified, color: scheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado del cupo gratuito: cuántos productos quedan y, si el paywall se
/// abrió desde el bloqueo, por qué se detuvo el registro.
class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.text,
    required this.used,
    required this.limit,
    required this.blocked,
    required this.blockedText,
  });

  final String text;
  final int used;
  final int limit;
  final bool blocked;
  final String blockedText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = limit <= 0 ? 1.0 : (used / limit).clamp(0.0, 1.0);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                color: ratio >= 1 ? scheme.error : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            if (blocked) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      blockedText,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tabla comparativa Gratis vs PRO.
class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({
    required this.features,
    required this.tr,
    required this.fill,
  });

  final List<_PlanFeature> features;
  final _Tr tr;
  final _Fill fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    tr(AppStrings.paywallColumnFeature),
                    style: labelStyle,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    tr(AppStrings.paywallColumnFree),
                    textAlign: TextAlign.center,
                    style: labelStyle,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    tr(AppStrings.paywallColumnPro),
                    textAlign: TextAlign.center,
                    style: labelStyle.copyWith(color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
          for (final feature in features) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            _FeatureRow(feature: feature, tr: tr, fill: fill),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.feature,
    required this.tr,
    required this.fill,
  });

  final _PlanFeature feature;
  final _Tr tr;
  final _Fill fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final args = {'limit': AppConstants.freeProductLimit};

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Icon(
                  feature.icon,
                  size: 16,
                  color: feature.highlight ? scheme.primary : scheme.outline,
                ),
                if (feature.highlight) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.bolt, size: 16, color: scheme.primary),
                ],
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr(feature.titleKey),
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              fill(feature.freeKey, args: args),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                decoration: feature.highlight
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              fill(feature.proKey, args: args),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Precio de la suscripción tal como lo publica Google Play.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({
    required this.offer,
    required this.loading,
    required this.loadingText,
    required this.unavailableText,
    required this.planName,
  });

  final SubscriptionOffer? offer;
  final bool loading;
  final String loadingText;
  final String unavailableText;
  final String planName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final description = offer?.description;
    final detail = description ??
        (loading ? loadingText : unavailableText);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                planName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  color: description == null
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (offer != null)
          Chip(
            avatar: const Icon(Icons.verified, size: 16),
            label: Text(offer!.price),
            backgroundColor: scheme.primaryContainer,
            side: BorderSide.none,
            labelStyle: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

/// Mensaje de la última operación de compra o restauración.
class _Notice extends StatelessWidget {
  const _Notice({required this.notice, required this.tr});

  final ProNotice notice;
  final _Tr tr;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = switch (notice) {
      ProNotice.purchased => AppStrings.paywallNoticePurchased,
      ProNotice.pending => AppStrings.paywallNoticePending,
      ProNotice.priceUnavailable => AppStrings.paywallNoticePrice,
      ProNotice.purchaseFailed => AppStrings.paywallNoticeFailed,
      ProNotice.nothingToRestore => AppStrings.paywallNoticeNothingToRestore,
      ProNotice.none => null,
    };
    if (key == null) return const SizedBox.shrink();

    final calm = notice == ProNotice.purchased ||
        notice == ProNotice.pending ||
        notice == ProNotice.priceUnavailable;
    final color = calm ? scheme.primary : scheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            calm ? Icons.info_outline : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(key),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
