import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/audio/sound_feedback.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/product.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/movement_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../features/license/license_service.dart';
import '../../features/products/product_form_screen.dart';
import '../../features/products/product_provider.dart';
import '../../features/sales/sales_provider.dart';
import '../../features/shifts/shift_close_dialog.dart';
import '../../features/shifts/shift_open_dialog.dart';
import '../../features/shifts/shift_provider.dart';
import '../../services/scanner_input_service.dart';
import '../sales/sales_history_view.dart';
import 'cart_item.dart';
import 'cart_provider.dart';
import 'ticket_z_dialog.dart';

/// Vista base del Punto de Venta, optimizada para escritorio (Windows).
///
/// Distribución 60/40: catálogo con buscador a la izquierda y ticket de la
/// venta activa a la derecha. Sin componentes de cámara: la lectura entra por
/// el [TextField] del buscador (pistola USB/Bluetooth que emula teclado).
///
/// Atajos:
///  - `F12`: abrir el cobro.
///  - `Esc`: vaciar la venta actual.
///  - `Enter` (fuera del buscador): abrir el cobro.
class PosDesktopView extends StatefulWidget {
  const PosDesktopView({super.key});

  @override
  State<PosDesktopView> createState() => _PosDesktopViewState();
}

class _PosDesktopViewState extends State<PosDesktopView>
    implements ScannerInputSink {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _query = '';
  bool _checkoutOpen = false;

  final StringBuffer _gunBuffer = StringBuffer();

  @override
  void initState() {
    super.initState();
    ScannerInputService.instance.register(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductProvider>().load();
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    ScannerInputService.instance.unregister(this);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void clearBuffer() {
    _gunBuffer.clear();
  }

  @override
  bool handleGunKey(KeyEvent event) => _hardwareKey(event);

  /// Escucha global de teclado para pistolas USB/Bluetooth (emulan teclado).
  /// Acumula caracteres; al recibir Enter con el foco FUERA del buscador
  /// procesa la tira completa como lectura de código. Si el foco está en el
  /// campo, el Enter lo resuelve [onSubmitted] sin duplicar.
  /// Retorna `true` (consumido) solo cuando finalizó una lectura completa.
  bool _hardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || _checkoutOpen) return false;

    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;

    if (isEnter && _searchFocus.hasFocus) {
      _gunBuffer.clear();
      return false;
    }

    if (isEnter) {
      final text = _gunBuffer.toString();
      _gunBuffer.clear();
      if (normalizeBarcode(text).isEmpty) return false;
      unawaited(_processRead(text));
      return true;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && !_searchFocus.hasFocus) {
      _gunBuffer.write(char);
    }
    return false;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final enter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;

    // Enter con el foco fuera del buscador equivale a pulsar F12.
    if (enter && !_searchFocus.hasFocus && !_checkoutOpen) {
      _openCheckout();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Atajo `F12`: abre el modal de cobro.
  Future<void> _onF12() async {
    if (!_checkoutOpen) await _openCheckout();
  }

  /// Atajo `Esc`: vacía la venta actual (con confirmación).
  Future<void> _onEscape() async {
    if (_searchFocus.hasFocus || _checkoutOpen) return;
    await _confirmClearCart();
  }

  /// Devuelve el foco al buscador para la próxima lectura de la pistola.
  void _keepSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  Future<void> _onSearchSubmitted() async {
    _gunBuffer.clear();
    final text = _searchController.text;
    if (normalizeBarcode(text).isEmpty) return;
    unawaited(_processRead(text));
  }

  /// Procesa una lectura de código (pistola o digitación manual): busca en la
  /// base local, agrega al ticket o muestra un aviso para crearlo.
  Future<void> _processRead(String raw) async {
    final text = normalizeBarcode(raw);
    if (text.isEmpty) return;

    Product? match;
    try {
      match = await context.read<ProductRepository>().byBarcode(text);
    } catch (_) {
      match = null;
    }
    if (!mounted) return;

    if (match == null) {
      _showUnknownCode(text);
      return;
    }

    _addToCart(match);
    _searchController.clear();
    if (mounted) setState(() => _query = '');
    _keepSearchFocus();
  }

  /// Código no encontrado: aviso no bloqueante con opción de crear producto.
  void _showUnknownCode(String code) {
    unawaited(SoundFeedback.error());
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Código "$code" no está en el catálogo'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Crear producto',
            onPressed: () => _createProduct(code),
          ),
        ),
      );
  }

  Future<void> _createProduct(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(initialBarcode: code),
      ),
    );
    if (created == true && mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('Producto creado')));
      context.read<ProductProvider>().load();
      _keepSearchFocus();
    }
  }

  void _addToCart(Product product) {
    context.read<CartProvider>().addProduct(product);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${product.name} · +1'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    unawaited(SoundFeedback.success());
  }

  Future<void> _openCheckout() async {
    final messenger = ScaffoldMessenger.of(context);
    final cart = context.read<CartProvider>();
    final salesProvider = context.read<SalesProvider>();
    final productProvider = context.read<ProductProvider>();

    // Gate por Turnos y Cajas: sin turno abierto no se puede vender.
    final shifts = context.read<ShiftProvider>();
    if (!shifts.hasActiveShift) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Abre un turno de caja para comenzar a vender.'),
          duration: Duration(seconds: 4),
        ));
      return;
    }
    final shiftId = shifts.activeShift?.id?.toString();

    // Bloqueo por licencia de hardware (solo si la nube ya respondió que el
    // dispositivo NO está autorizado).
    final license = context.read<LicenseService>();
    if (license.isBlockingSales) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text(
            'Licencia inválida o expirada en este equipo.\n'
            'Contacta al administrador para reactivar el dispositivo.',
          ),
          duration: Duration(seconds: 6),
        ));
      return;
    }

    if (cart.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('La venta está vacía')));
      return;
    }

    final insufficient = cart.items
        .where((item) => item.quantity > item.product.quantity)
        .toList();
    if (insufficient.isNotEmpty) {
      final detail = insufficient
          .map((item) =>
              '${item.product.name} (stock: ${item.product.quantity})')
          .join(', ');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Stock insuficiente: $detail')));
      return;
    }

    final items = List<CartItem>.from(cart.items);
    final subtotal = cart.subtotal;
    final tax = cart.tax;
    final taxRate = cart.taxRate;
    final total = cart.total;
    setState(() => _checkoutOpen = true);
    final result = await showDialog<_CheckoutResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CheckoutDialog(cart: cart),
    );
    setState(() => _checkoutOpen = false);
    if (!mounted) return;
    if (result == null) {
      _searchFocus.requestFocus();
      return;
    }

    // Descuenta el stock vendido como movimiento de salida.
    final movements = context.read<MovementRepository>();
    final errors = <String>[];
    for (final item in items) {
      final id = item.product.id;
      if (id == null) continue;
      try {
        await movements.adjustStock(id, -item.quantity);
      } catch (_) {
        errors.add(item.product.name);
      }
    }
    if (!mounted) return;

    // Persiste la venta en el historial.
    final saleId = await salesProvider.registrarVenta(
          items: items,
          method: result.method,
          subtotal: subtotal,
          taxRate: taxRate,
          tax: tax,
          total: total,
          received: result.received,
          change: result.change,
          shiftId: shiftId,
        );

    cart.clearCart();
    productProvider.load();
    unawaited(SoundFeedback.operation());
    _searchFocus.requestFocus();

    final message = saleId == null
        ? 'Venta no registrada en el historial · ${formatMoney(total)}'
        : errors.isEmpty
            ? 'Venta registrada · ${formatMoney(total)}'
            : 'Venta con errores en stock: ${errors.join(', ')}';
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openShiftDialog() async {
    _searchFocus.unfocus();
    await showDialog<bool>(
      context: context,
      builder: (_) => const ShiftOpenDialog(),
    );
    _keepSearchFocus();
  }

  Future<void> _closeShiftDialog() async {
    _searchFocus.unfocus();
    final result = await showDialog<ShiftCloseResult>(
      context: context,
      builder: (_) => const ShiftCloseDialog(),
    );
    if (result != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => TicketZDialog(result: result),
      );
    }
    _keepSearchFocus();
  }

  Future<void> _confirmClearCart() async {
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).posClearSaleTitle),
        content: Text(AppLocalizations.of(ctx).posClearSalePrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(ctx).commonClear),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    cart.clearCart();
    _searchFocus.requestFocus();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ProductProvider>();
    final cart = context.watch<CartProvider>();
    final shifts = context.watch<ShiftProvider>();

    final query = _query.trim().toLowerCase();
    final products = catalog.products.where((product) {
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);
    }).toList();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f12): _onF12,
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _onKeyEvent,
        // Caja cerrada ⇒ sin AppBar y sin retroceso: PopScope bloquea el
        // retroceso por teclado/mouse; además se oculta TODA la barra de
        // navegación superior. Con turno abierto, "Salir al menú" vive al
        // EXTREMO DERECHO, separado por la info de la venta activa y por
        // separadores, para que jamás se sobreponga con "Cerrar caja".
        child: PopScope(
          canPop: shifts.hasActiveShift,
          child: Scaffold(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerLowest,
            appBar: !shifts.hasActiveShift
                ? null
                : AppBar(
                    automaticallyImplyLeading: false,
                    title: Text(AppLocalizations.of(context).posTitle),
                    actions: [
                      Tooltip(
                        message: AppLocalizations.of(context).posCloseShift,
                        child: TextButton.icon(
                          onPressed: _closeShiftDialog,
                          icon: const Icon(Icons.lock, size: 18),
                          label: Text(shifts.registerName),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          _searchFocus.unfocus();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SalesHistoryView(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(
                          AppLocalizations.of(context).posViewSales,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Center(
                          child: Text(
                            cart.isEmpty
                                ? AppLocalizations.of(context).posNoActiveSale
                                : '${cart.totalUnits} ítem(s) · ${formatMoney(cart.total)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: AppLocalizations.of(context).posExitMenu,
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
            body: _buildBody(shifts, catalog, products, cart),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    ShiftProvider shifts,
    ProductProvider catalog,
    List<Product> products,
    CartProvider cart,
  ) {
    if (shifts.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!shifts.hasActiveShift) return _buildShiftLocked(shifts);
    return GestureDetector(
      // Cualquier clic sobre zonas vacías devuelve el foco al buscador.
      behavior: HitTestBehavior.translucent,
      onTap: _keepSearchFocus,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchBar(),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildCatalog(catalog, products),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildTicket(cart),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftLocked(ShiftProvider shifts) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 72, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            'Caja ${shifts.registerName} cerrada',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Abre el turno para comenzar a vender.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openShiftDialog,
            icon: const Icon(Icons.point_of_sale),
            label: const Text('Abrir turno'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          autofocus: true,
          onChanged: (value) => setState(() => _query = value),
          onSubmitted: (value) => _onSearchSubmitted(),
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Buscar o escanear',
            hintText: 'Código de barras o nombre · Enter agrega al ticket',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: AppLocalizations.of(context).posClearSearch,
                    onPressed: _clearSearch,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalog(ProductProvider catalog, List<Product> products) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Catálogo · toca un producto para agregarlo',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: _gridOrStatus(catalog, products),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridOrStatus(ProductProvider catalog, List<Product> products) {
    if (catalog.loading && catalog.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.error != null && catalog.products.isEmpty) {
      return _CenterStatus(
        icon: Icons.cloud_off_outlined,
        title: catalog.error!,
      );
    }
    if (products.isEmpty) {
      return _CenterStatus(
        icon: catalog.products.isEmpty
            ? Icons.inventory_2_outlined
            : Icons.search_off,
        title: catalog.products.isEmpty
            ? 'Sin productos aún'
            : 'Sin resultados para "$_query"',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 190).floor().clamp(1, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 214,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return _ProductPosCard(
              product: product,
              onTap: () => _addToCart(product),
            );
          },
        );
      },
    );
  }

  Widget _buildTicket(CartProvider cart) {
    final scheme = Theme.of(context).colorScheme;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Venta actual',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: cart.isEmpty ? null : _confirmClearCart,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Vaciar'),
          ),
        ],
      ),
    );

    final itemTiles = [
      if (cart.isEmpty)
        const _CenterStatus(
          icon: Icons.shopping_cart_outlined,
          title: 'Sin productos en la venta',
        )
      else
        for (final item in cart.items)
          _TicketItemTile(
            item: item,
            onIncrement: () => cart.increment(item.product),
            onDecrement: () => cart.decrement(item.product),
            onRemove: () => cart.removeProduct(item.product),
          ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // En ventanas muy bajas el ticket entra en modo scroll (la lista
          // deja de usar Expanded) para nunca desbordar en vertical.
          final scrollMode = constraints.maxHeight < 500;
          final itemsArea = Expanded(
            child: scrollMode
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < itemTiles.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          itemTiles[i],
                        ],
                      ],
                    ),
                  )
                : cart.isEmpty
                    ? itemTiles.first
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: cart.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = cart.items[index];
                          return _TicketItemTile(
                            item: item,
                            onIncrement: () => cart.increment(item.product),
                            onDecrement: () => cart.decrement(item.product),
                            onRemove: () => cart.removeProduct(item.product),
                          );
                        },
                      ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const Divider(height: 1),
              itemsArea,
              _TicketFooter(
                cart: cart,
                onCheckout: _openCheckout,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductPosCard extends StatelessWidget {
  const _ProductPosCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final low = product.isLowStock;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: low ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProductPhoto(product: product),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      product.barcode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          formatMoney(product.price),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        _StockBadge(
                          quantity: product.quantity,
                          low: low,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPhoto extends StatelessWidget {
  const _ProductPhoto({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = product.imagePath;
    final Widget placeholder = Container(
      color: scheme.primaryContainer.withValues(alpha: 0.5),
      child: Icon(
        Icons.qr_code_2,
        size: 40,
        color: scheme.onPrimaryContainer.withValues(alpha: 0.6),
      ),
    );

    Widget child = placeholder;
    if (!kIsWeb && path != null && path.isNotEmpty) {
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    return SizedBox(
      height: 84,
      width: double.infinity,
      child: child,
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.quantity, required this.low});

  final int quantity;
  final bool low;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = low ? scheme.error : scheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          low ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$quantity',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _TicketItemTile extends StatelessWidget {
  const _TicketItemTile({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '${item.product.barcode} · ${formatMoney(item.product.price)} c/u',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final Widget subtotal = Text(
      formatMoney(item.subtotal),
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;

        if (compact) {
          // Columnas angostas: nombre arriba, controles y total abajo.
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: info),
                    _SmallIconButton(
                      tooltip: AppLocalizations.of(context).posRemoveItem,
                      icon: Icons.delete_outline,
                      color: scheme.error,
                      onPressed: onRemove,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _QuantityControl(
                      quantity: item.quantity,
                      compact: true,
                      onDecrement: onDecrement,
                      onIncrement: onIncrement,
                    ),
                    const Spacer(),
                    Flexible(child: subtotal),
                  ],
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(child: info),
              _SmallIconButton(
                tooltip: AppLocalizations.of(context).posRemoveItem,
                icon: Icons.delete_outline,
                color: scheme.error,
                onPressed: onRemove,
              ),
              _QuantityControl(
                quantity: item.quantity,
                onDecrement: onDecrement,
                onIncrement: onIncrement,
              ),
              SizedBox(
                width: 96,
                child: subtotal,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
    this.compact = false,
  });

  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget button({
      required String tooltip,
      required IconData icon,
      required VoidCallback onPressed,
    }) {
      if (compact) {
        return _SmallIconButton(
          tooltip: tooltip,
          icon: icon,
          onPressed: onPressed,
        );
      }
      return IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon),
        visualDensity: VisualDensity.compact,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          tooltip: 'Restar',
          icon: Icons.remove_circle_outline,
          onPressed: onDecrement,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        button(
          tooltip: 'Sumar',
          icon: Icons.add_circle_outline,
          onPressed: onIncrement,
        ),
      ],
    );
  }
}

class _TicketFooter extends StatelessWidget {
  const _TicketFooter({required this.cart, required this.onCheckout});

  final CartProvider cart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MoneyRow(label: 'Subtotal', value: cart.subtotal),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: FilterChip(
                  selected: cart.taxRate > 0,
                  avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('IVA 19%'),
                  visualDensity: VisualDensity.compact,
                  onSelected: (selected) =>
                      cart.setTaxRate(selected ? 0.19 : 0.0),
                ),
              ),
              const Spacer(),
              if (cart.taxRate > 0)
                Text(
                  formatMoney(cart.tax),
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatMoney(cart.total),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: cart.isEmpty ? null : onCheckout,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.payments_outlined),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'COBRAR / FINALIZAR VENTA',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'F12 o Enter: cobrar · Esc: vaciar venta',
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
        Flexible(
          child: Text(
            formatMoney(value),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Resultado del cobro confirmado: método de pago y montos.
class _CheckoutResult {
  const _CheckoutResult({
    required this.method,
    required this.received,
    required this.change,
  });

  final PaymentMethod method;
  final double received;
  final double change;
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({required this.cart});

  final CartProvider cart;

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  late PaymentMethod _method;
  late final TextEditingController _receivedController;

  double get _total => widget.cart.total;

  double get _received =>
      double.tryParse(_receivedController.text.replaceAll(',', '.')) ?? 0;

  double get _change =>
      _method == PaymentMethod.efectivo && _received >= _total
          ? _received - _total
          : 0;

  bool get _insufficient =>
      _method == PaymentMethod.efectivo && _received < _total;

  @override
  void initState() {
    super.initState();
    _method = PaymentMethod.efectivo;
    // El monto recibido se pre-carga redondeando hacia arriba para agilizar
    // el cobro en efectivo.
    _receivedController =
        TextEditingController(text: _total.ceilToDouble().toString());
  }

  @override
  void dispose() {
    _receivedController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop(
      _CheckoutResult(
        method: _method,
        received: _method == PaymentMethod.efectivo ? _received : _total,
        change: _change,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cart = widget.cart;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.posCheckoutTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SingleChildScrollView (no shrink-wrap): permite intrínsecos en
            // AlertDialog sin lanzar "RenderShrinkWrappingViewport".
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in cart.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.product.name} × ${item.quantity}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              formatMoney(item.subtotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            _MoneyRow(label: 'Subtotal', value: cart.subtotal),
            if (cart.taxRate > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _MoneyRow(label: 'Impuesto', value: cart.tax),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(_total),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<PaymentMethod>(
              segments: [
                ButtonSegment(
                  value: PaymentMethod.efectivo,
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(l10n.commonEfectivo),
                ),
                ButtonSegment(
                  value: PaymentMethod.tarjeta,
                  icon: const Icon(Icons.credit_card),
                  label: Text(l10n.commonTarjeta),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (selection) =>
                  setState(() => _method = selection.first),
            ),
            if (_method == PaymentMethod.efectivo) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _receivedController,
                onChanged: (_) => setState(() {}),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: const InputDecoration(
                  labelText: 'Recibido de',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 6),
              _MoneyRow(label: 'Vuelto', value: _change),
              if (_insufficient) ...[
                const SizedBox(height: 6),
                Text(
                  'Falta dinero: necesitas al menos ${formatMoney(_total)}',
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _insufficient ? null : _confirm,
          child: Text(l10n.posConfirmSale),
        ),
      ],
    );
  }
}

class _CenterStatus extends StatelessWidget {
  const _CenterStatus({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}