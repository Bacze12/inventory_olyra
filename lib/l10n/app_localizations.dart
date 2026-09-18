import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In es, this message translates to:
  /// **'BodegaFlow'**
  String get appTitle;

  /// No description provided for @menuProducts.
  ///
  /// In es, this message translates to:
  /// **'Productos'**
  String get menuProducts;

  /// No description provided for @menuProductsSub.
  ///
  /// In es, this message translates to:
  /// **'Catálogo y stock'**
  String get menuProductsSub;

  /// No description provided for @menuReports.
  ///
  /// In es, this message translates to:
  /// **'Reporte PDF'**
  String get menuReports;

  /// No description provided for @menuReportsSub.
  ///
  /// In es, this message translates to:
  /// **'Exportar y guardar'**
  String get menuReportsSub;

  /// No description provided for @menuPrinter.
  ///
  /// In es, this message translates to:
  /// **'Imprimir etiqueta'**
  String get menuPrinter;

  /// No description provided for @menuPrinterSub.
  ///
  /// In es, this message translates to:
  /// **'Bluetooth / PDF'**
  String get menuPrinterSub;

  /// No description provided for @menuScanner.
  ///
  /// In es, this message translates to:
  /// **'Escáner'**
  String get menuScanner;

  /// No description provided for @menuScannerSubHandheld.
  ///
  /// In es, this message translates to:
  /// **'Pistola en cualquier pantalla'**
  String get menuScannerSubHandheld;

  /// No description provided for @menuScannerSubMobile.
  ///
  /// In es, this message translates to:
  /// **'Entradas y salidas'**
  String get menuScannerSubMobile;

  /// No description provided for @menuPair.
  ///
  /// In es, this message translates to:
  /// **'Vincular dispositivo'**
  String get menuPair;

  /// No description provided for @menuPairSub.
  ///
  /// In es, this message translates to:
  /// **'Emparejar esta PC con un celular (QR / PIN)'**
  String get menuPairSub;

  /// No description provided for @menuAboutTooltip.
  ///
  /// In es, this message translates to:
  /// **'Acerca de · Licencia'**
  String get menuAboutTooltip;

  /// No description provided for @menuCloudTitle.
  ///
  /// In es, this message translates to:
  /// **'Nube y respaldo'**
  String get menuCloudTitle;

  /// No description provided for @homeHeroTitle.
  ///
  /// In es, this message translates to:
  /// **'Inventario al instante'**
  String get homeHeroTitle;

  /// No description provided for @homeHeroSub.
  ///
  /// In es, this message translates to:
  /// **'Escanea y actualiza existencias sin conexión.'**
  String get homeHeroSub;

  /// No description provided for @homeHeroScan.
  ///
  /// In es, this message translates to:
  /// **'Escanear ahora'**
  String get homeHeroScan;

  /// No description provided for @posMenuTitle.
  ///
  /// In es, this message translates to:
  /// **'Punto de venta'**
  String get posMenuTitle;

  /// No description provided for @posMenuSub.
  ///
  /// In es, this message translates to:
  /// **'Venta rápida en PC · F12 para cobrar'**
  String get posMenuSub;

  /// No description provided for @salesHistoryMenuTitle.
  ///
  /// In es, this message translates to:
  /// **'Historial de ventas'**
  String get salesHistoryMenuTitle;

  /// No description provided for @salesHistoryMenuSub.
  ///
  /// In es, this message translates to:
  /// **'Ventas del POS · detalle y anulación'**
  String get salesHistoryMenuSub;

  /// No description provided for @menuSyncTitle.
  ///
  /// In es, this message translates to:
  /// **'Sincronizar con PC'**
  String get menuSyncTitle;

  /// No description provided for @menuSyncSub.
  ///
  /// In es, this message translates to:
  /// **'Bajar catálogo y subir ventas (Wi-Fi)'**
  String get menuSyncSub;

  /// No description provided for @menuDiagnose.
  ///
  /// In es, this message translates to:
  /// **'Probar conexión (diagnóstico)'**
  String get menuDiagnose;

  /// No description provided for @cloudNeedsActivation.
  ///
  /// In es, this message translates to:
  /// **'Licencia no activa: activa antes de sincronizar'**
  String get cloudNeedsActivation;

  /// No description provided for @cloudValidating.
  ///
  /// In es, this message translates to:
  /// **'Validando con olyra.cl…'**
  String get cloudValidating;

  /// No description provided for @cloudSyncing.
  ///
  /// In es, this message translates to:
  /// **'Sincronizando…'**
  String get cloudSyncing;

  /// No description provided for @cloudError.
  ///
  /// In es, this message translates to:
  /// **'Error de sincronización · reintenta'**
  String get cloudError;

  /// No description provided for @cloudActive.
  ///
  /// In es, this message translates to:
  /// **'Nube Activa · Sincronizado'**
  String get cloudActive;

  /// No description provided for @cloudUnconfigured.
  ///
  /// In es, this message translates to:
  /// **'Nube lista · revalida para conectar'**
  String get cloudUnconfigured;

  /// No description provided for @productListTitle.
  ///
  /// In es, this message translates to:
  /// **'Productos'**
  String get productListTitle;

  /// No description provided for @productDeleteTitle.
  ///
  /// In es, this message translates to:
  /// **'Eliminar producto'**
  String get productDeleteTitle;

  /// No description provided for @posTitle.
  ///
  /// In es, this message translates to:
  /// **'Punto de venta'**
  String get posTitle;

  /// No description provided for @posCloseShift.
  ///
  /// In es, this message translates to:
  /// **'Cerrar caja'**
  String get posCloseShift;

  /// No description provided for @posViewSales.
  ///
  /// In es, this message translates to:
  /// **'Ver Ventas'**
  String get posViewSales;

  /// No description provided for @posNoActiveSale.
  ///
  /// In es, this message translates to:
  /// **'Sin venta activa'**
  String get posNoActiveSale;

  /// No description provided for @posExitMenu.
  ///
  /// In es, this message translates to:
  /// **'Salir al menú'**
  String get posExitMenu;

  /// No description provided for @posClearSaleTitle.
  ///
  /// In es, this message translates to:
  /// **'Vaciar venta'**
  String get posClearSaleTitle;

  /// No description provided for @posClearSalePrompt.
  ///
  /// In es, this message translates to:
  /// **'¿Vaciar la venta actual? Los ítems se descartan.'**
  String get posClearSalePrompt;

  /// No description provided for @posCheckoutTitle.
  ///
  /// In es, this message translates to:
  /// **'Finalizar venta'**
  String get posCheckoutTitle;

  /// No description provided for @posConfirmSale.
  ///
  /// In es, this message translates to:
  /// **'Confirmar venta'**
  String get posConfirmSale;

  /// No description provided for @posRemoveItem.
  ///
  /// In es, this message translates to:
  /// **'Quitar de la venta'**
  String get posRemoveItem;

  /// No description provided for @posClearSearch.
  ///
  /// In es, this message translates to:
  /// **'Limpiar búsqueda'**
  String get posClearSearch;

  /// No description provided for @commonCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// No description provided for @commonClear.
  ///
  /// In es, this message translates to:
  /// **'Vaciar'**
  String get commonClear;

  /// No description provided for @commonDone.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get commonDone;

  /// No description provided for @commonEfectivo.
  ///
  /// In es, this message translates to:
  /// **'Efectivo'**
  String get commonEfectivo;

  /// No description provided for @commonTarjeta.
  ///
  /// In es, this message translates to:
  /// **'Tarjeta'**
  String get commonTarjeta;

  /// No description provided for @shiftsOpenTitle.
  ///
  /// In es, this message translates to:
  /// **'Abrir turno de caja'**
  String get shiftsOpenTitle;

  /// No description provided for @shiftsCloseTitle.
  ///
  /// In es, this message translates to:
  /// **'Cerrar caja · Ticket Z'**
  String get shiftsCloseTitle;

  /// No description provided for @shiftsTicketTitle.
  ///
  /// In es, this message translates to:
  /// **'Ticket Z · Cierre de caja'**
  String get shiftsTicketTitle;

  /// No description provided for @shiftsExpectedCash.
  ///
  /// In es, this message translates to:
  /// **'Efectivo esperado'**
  String get shiftsExpectedCash;

  /// No description provided for @shiftsCountedCash.
  ///
  /// In es, this message translates to:
  /// **'Efectivo contado en caja'**
  String get shiftsCountedCash;

  /// No description provided for @shiftsUseExpected.
  ///
  /// In es, this message translates to:
  /// **'Usar saldo esperado'**
  String get shiftsUseExpected;

  /// No description provided for @shiftsCashSales.
  ///
  /// In es, this message translates to:
  /// **'Efectivo ventas'**
  String get shiftsCashSales;

  /// No description provided for @shiftsCardSales.
  ///
  /// In es, this message translates to:
  /// **'Tarjeta ventas'**
  String get shiftsCardSales;

  /// No description provided for @shiftsTotalSales.
  ///
  /// In es, this message translates to:
  /// **'Total ventas'**
  String get shiftsTotalSales;

  /// No description provided for @shiftsCountedLabel.
  ///
  /// In es, this message translates to:
  /// **'Efectivo contado'**
  String get shiftsCountedLabel;

  /// No description provided for @shiftsDifference.
  ///
  /// In es, this message translates to:
  /// **'Diferencia'**
  String get shiftsDifference;

  /// No description provided for @shiftsRegMatch.
  ///
  /// In es, this message translates to:
  /// **'El cuadre coincide. Caja cerrada.'**
  String get shiftsRegMatch;

  /// No description provided for @shiftsRegShort.
  ///
  /// In es, this message translates to:
  /// **'Falta efectivo en caja.'**
  String get shiftsRegShort;

  /// No description provided for @shiftsRegOver.
  ///
  /// In es, this message translates to:
  /// **'Sobra efectivo en caja.'**
  String get shiftsRegOver;

  /// No description provided for @shiftsRegister.
  ///
  /// In es, this message translates to:
  /// **'Caja'**
  String get shiftsRegister;

  /// No description provided for @shiftsDate.
  ///
  /// In es, this message translates to:
  /// **'Fecha'**
  String get shiftsDate;

  /// No description provided for @shiftsCashier.
  ///
  /// In es, this message translates to:
  /// **'Cajero'**
  String get shiftsCashier;

  /// No description provided for @shiftsOpenedAt.
  ///
  /// In es, this message translates to:
  /// **'Abierto'**
  String get shiftsOpenedAt;

  /// No description provided for @shiftsOpeningFund.
  ///
  /// In es, this message translates to:
  /// **'Fondo inicial'**
  String get shiftsOpeningFund;

  /// No description provided for @shiftsPin.
  ///
  /// In es, this message translates to:
  /// **'PIN del cajero'**
  String get shiftsPin;

  /// No description provided for @shiftsExpectedPlaceholder.
  ///
  /// In es, this message translates to:
  /// **'calculando…'**
  String get shiftsExpectedPlaceholder;

  /// No description provided for @shiftsCountedHelper.
  ///
  /// In es, this message translates to:
  /// **'Se precarga el saldo esperado para que cuadre.'**
  String get shiftsCountedHelper;

  /// No description provided for @shiftsCloseAction.
  ///
  /// In es, this message translates to:
  /// **'Cerrar caja'**
  String get shiftsCloseAction;

  /// No description provided for @salesHistoryTitle.
  ///
  /// In es, this message translates to:
  /// **'Historial de ventas'**
  String get salesHistoryTitle;

  /// No description provided for @saleDetailTitle.
  ///
  /// In es, this message translates to:
  /// **'Detalle de venta'**
  String get saleDetailTitle;

  /// No description provided for @saleVoidTitle.
  ///
  /// In es, this message translates to:
  /// **'Anular venta'**
  String get saleVoidTitle;

  /// No description provided for @reportsTitle.
  ///
  /// In es, this message translates to:
  /// **'Reporte de inventario'**
  String get reportsTitle;

  /// No description provided for @reportsStoreName.
  ///
  /// In es, this message translates to:
  /// **'Nombre del negocio'**
  String get reportsStoreName;

  /// No description provided for @reportsGenerate.
  ///
  /// In es, this message translates to:
  /// **'Generar reporte PDF'**
  String get reportsGenerate;

  /// No description provided for @reportsSave.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get reportsSave;

  /// No description provided for @reportsShare.
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get reportsShare;

  /// No description provided for @reportsPrint.
  ///
  /// In es, this message translates to:
  /// **'Imprimir'**
  String get reportsPrint;

  /// No description provided for @reportsProducts.
  ///
  /// In es, this message translates to:
  /// **'Productos'**
  String get reportsProducts;

  /// No description provided for @reportsUnits.
  ///
  /// In es, this message translates to:
  /// **'Unidades'**
  String get reportsUnits;

  /// No description provided for @reportsLowStock.
  ///
  /// In es, this message translates to:
  /// **'Stock bajo'**
  String get reportsLowStock;

  /// No description provided for @reportsHint.
  ///
  /// In es, this message translates to:
  /// **'Genera el reporte para verlo en pantalla.'**
  String get reportsHint;

  /// No description provided for @reportsErrorGenerate.
  ///
  /// In es, this message translates to:
  /// **'No se pudo generar el reporte'**
  String get reportsErrorGenerate;

  /// No description provided for @reportsErrorSave.
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar el reporte'**
  String get reportsErrorSave;

  /// No description provided for @reportsErrorShare.
  ///
  /// In es, this message translates to:
  /// **'Error al compartir el reporte'**
  String get reportsErrorShare;

  /// Confirmación al guardar el reporte.
  ///
  /// In es, this message translates to:
  /// **'Guardado en:\n{path}'**
  String reportsSavedAt(String path);

  /// No description provided for @scannerEntrada.
  ///
  /// In es, this message translates to:
  /// **'Entrada'**
  String get scannerEntrada;

  /// No description provided for @scannerSalida.
  ///
  /// In es, this message translates to:
  /// **'Salida'**
  String get scannerSalida;

  /// No description provided for @scannerScanCode.
  ///
  /// In es, this message translates to:
  /// **'Escanear código'**
  String get scannerScanCode;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
