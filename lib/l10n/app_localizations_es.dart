// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'BodegaFlow';

  @override
  String get menuProducts => 'Productos';

  @override
  String get menuProductsSub => 'Catálogo y stock';

  @override
  String get menuReports => 'Reporte PDF';

  @override
  String get menuReportsSub => 'Exportar y guardar';

  @override
  String get menuPrinter => 'Imprimir etiqueta';

  @override
  String get menuPrinterSub => 'Bluetooth / PDF';

  @override
  String get menuScanner => 'Escáner';

  @override
  String get menuScannerSubHandheld => 'Pistola en cualquier pantalla';

  @override
  String get menuScannerSubMobile => 'Entradas y salidas';

  @override
  String get menuPair => 'Vincular dispositivo';

  @override
  String get menuPairSub => 'Emparejar esta PC con un celular (QR / PIN)';

  @override
  String get menuAboutTooltip => 'Acerca de · Licencia';

  @override
  String get menuCloudTitle => 'Nube y respaldo';

  @override
  String get homeHeroTitle => 'Inventario al instante';

  @override
  String get homeHeroSub => 'Escanea y actualiza existencias sin conexión.';

  @override
  String get homeHeroScan => 'Escanear ahora';

  @override
  String get posMenuTitle => 'Punto de venta';

  @override
  String get posMenuSub => 'Venta rápida en PC · F12 para cobrar';

  @override
  String get salesHistoryMenuTitle => 'Historial de ventas';

  @override
  String get salesHistoryMenuSub => 'Ventas del POS · detalle y anulación';

  @override
  String get menuSyncTitle => 'Sincronizar con PC';

  @override
  String get menuSyncSub => 'Bajar catálogo y subir ventas (Wi-Fi)';

  @override
  String get menuDiagnose => 'Probar conexión (diagnóstico)';

  @override
  String get cloudNeedsActivation =>
      'Licencia no activa: activa antes de sincronizar';

  @override
  String get cloudValidating => 'Validando con olyra.cl…';

  @override
  String get cloudSyncing => 'Sincronizando…';

  @override
  String get cloudError => 'Error de sincronización · reintenta';

  @override
  String get cloudActive => 'Nube Activa · Sincronizado';

  @override
  String get cloudUnconfigured => 'Nube lista · revalida para conectar';

  @override
  String get productListTitle => 'Productos';

  @override
  String get productDeleteTitle => 'Eliminar producto';

  @override
  String get posTitle => 'Punto de venta';

  @override
  String get posCloseShift => 'Cerrar caja';

  @override
  String get posViewSales => 'Ver Ventas';

  @override
  String get posNoActiveSale => 'Sin venta activa';

  @override
  String get posExitMenu => 'Salir al menú';

  @override
  String get posClearSaleTitle => 'Vaciar venta';

  @override
  String get posClearSalePrompt =>
      '¿Vaciar la venta actual? Los ítems se descartan.';

  @override
  String get posCheckoutTitle => 'Finalizar venta';

  @override
  String get posConfirmSale => 'Confirmar venta';

  @override
  String get posRemoveItem => 'Quitar de la venta';

  @override
  String get posClearSearch => 'Limpiar búsqueda';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonClear => 'Vaciar';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonEfectivo => 'Efectivo';

  @override
  String get commonTarjeta => 'Tarjeta';

  @override
  String get shiftsOpenTitle => 'Abrir turno de caja';

  @override
  String get shiftsCloseTitle => 'Cerrar caja · Ticket Z';

  @override
  String get shiftsTicketTitle => 'Ticket Z · Cierre de caja';

  @override
  String get shiftsExpectedCash => 'Efectivo esperado';

  @override
  String get shiftsCountedCash => 'Efectivo contado en caja';

  @override
  String get shiftsUseExpected => 'Usar saldo esperado';

  @override
  String get shiftsCashSales => 'Efectivo ventas';

  @override
  String get shiftsCardSales => 'Tarjeta ventas';

  @override
  String get shiftsTotalSales => 'Total ventas';

  @override
  String get shiftsCountedLabel => 'Efectivo contado';

  @override
  String get shiftsDifference => 'Diferencia';

  @override
  String get shiftsRegMatch => 'El cuadre coincide. Caja cerrada.';

  @override
  String get shiftsRegShort => 'Falta efectivo en caja.';

  @override
  String get shiftsRegOver => 'Sobra efectivo en caja.';

  @override
  String get shiftsRegister => 'Caja';

  @override
  String get shiftsDate => 'Fecha';

  @override
  String get shiftsCashier => 'Cajero';

  @override
  String get shiftsOpenedAt => 'Abierto';

  @override
  String get shiftsOpeningFund => 'Fondo inicial';

  @override
  String get shiftsPin => 'PIN del cajero';

  @override
  String get shiftsExpectedPlaceholder => 'calculando…';

  @override
  String get shiftsCountedHelper =>
      'Se precarga el saldo esperado para que cuadre.';

  @override
  String get shiftsCloseAction => 'Cerrar caja';

  @override
  String get salesHistoryTitle => 'Historial de ventas';

  @override
  String get saleDetailTitle => 'Detalle de venta';

  @override
  String get saleVoidTitle => 'Anular venta';

  @override
  String get reportsTitle => 'Reporte de inventario';

  @override
  String get reportsStoreName => 'Nombre del negocio';

  @override
  String get reportsGenerate => 'Generar reporte PDF';

  @override
  String get reportsSave => 'Guardar';

  @override
  String get reportsShare => 'Compartir';

  @override
  String get reportsPrint => 'Imprimir';

  @override
  String get reportsProducts => 'Productos';

  @override
  String get reportsUnits => 'Unidades';

  @override
  String get reportsLowStock => 'Stock bajo';

  @override
  String get reportsHint => 'Genera el reporte para verlo en pantalla.';

  @override
  String get reportsErrorGenerate => 'No se pudo generar el reporte';

  @override
  String get reportsErrorSave => 'No se pudo guardar el reporte';

  @override
  String get reportsErrorShare => 'Error al compartir el reporte';

  @override
  String reportsSavedAt(String path) {
    return 'Guardado en:\n$path';
  }

  @override
  String get scannerEntrada => 'Entrada';

  @override
  String get scannerSalida => 'Salida';

  @override
  String get scannerScanCode => 'Escanear código';
}
