// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BodegaFlow';

  @override
  String get menuProducts => 'Products';

  @override
  String get menuProductsSub => 'Catalog & stock';

  @override
  String get menuReports => 'PDF Report';

  @override
  String get menuReportsSub => 'Export and save';

  @override
  String get menuPrinter => 'Print label';

  @override
  String get menuPrinterSub => 'Bluetooth / PDF';

  @override
  String get menuScanner => 'Scanner';

  @override
  String get menuScannerSubHandheld => 'Handheld on any screen';

  @override
  String get menuScannerSubMobile => 'Ins and out';

  @override
  String get menuPair => 'Link device';

  @override
  String get menuPairSub => 'Pair this PC with a phone (QR / PIN)';

  @override
  String get menuAboutTooltip => 'About · License';

  @override
  String get menuCloudTitle => 'Cloud & backup';

  @override
  String get homeHeroTitle => 'Instant inventory';

  @override
  String get homeHeroSub => 'Scan and update stock offline.';

  @override
  String get homeHeroScan => 'Scan now';

  @override
  String get posMenuTitle => 'Point of Sale';

  @override
  String get posMenuSub => 'Quick sale on PC · F12 to charge';

  @override
  String get salesHistoryMenuTitle => 'Sales history';

  @override
  String get salesHistoryMenuSub => 'POS sales · detail and void';

  @override
  String get menuSyncTitle => 'Sync with PC';

  @override
  String get menuSyncSub => 'Download catalog and upload sales (Wi-Fi)';

  @override
  String get menuDiagnose => 'Test connection (diagnostics)';

  @override
  String get cloudNeedsActivation =>
      'License not active: activate before syncing';

  @override
  String get cloudValidating => 'Validating with olyra.cl…';

  @override
  String get cloudSyncing => 'Syncing…';

  @override
  String get cloudError => 'Sync error · retry';

  @override
  String get cloudActive => 'Cloud Active · Synced';

  @override
  String get cloudUnconfigured => 'Cloud ready · revalidate to connect';

  @override
  String get productListTitle => 'Products';

  @override
  String get productDeleteTitle => 'Delete product';

  @override
  String get posTitle => 'Point of Sale';

  @override
  String get posCloseShift => 'Close till';

  @override
  String get posViewSales => 'View Sales';

  @override
  String get posNoActiveSale => 'No active sale';

  @override
  String get posExitMenu => 'Back to menu';

  @override
  String get posClearSaleTitle => 'Clear sale';

  @override
  String get posClearSalePrompt =>
      'Clear the current sale? The items will be discarded.';

  @override
  String get posCheckoutTitle => 'Finish sale';

  @override
  String get posConfirmSale => 'Confirm sale';

  @override
  String get posRemoveItem => 'Remove from sale';

  @override
  String get posClearSearch => 'Clear search';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonDone => 'Done';

  @override
  String get commonEfectivo => 'Cash';

  @override
  String get commonTarjeta => 'Card';

  @override
  String get shiftsOpenTitle => 'Open cash shift';

  @override
  String get shiftsCloseTitle => 'Close till · Z Report';

  @override
  String get shiftsTicketTitle => 'Z Report · Cash close';

  @override
  String get shiftsExpectedCash => 'Expected cash';

  @override
  String get shiftsCountedCash => 'Cash counted in till';

  @override
  String get shiftsUseExpected => 'Use expected balance';

  @override
  String get shiftsCashSales => 'Cash sales';

  @override
  String get shiftsCardSales => 'Card sales';

  @override
  String get shiftsTotalSales => 'Total sales';

  @override
  String get shiftsCountedLabel => 'Cash counted';

  @override
  String get shiftsDifference => 'Difference';

  @override
  String get shiftsRegMatch => 'The count matches. Till closed.';

  @override
  String get shiftsRegShort => 'Shortage in the till.';

  @override
  String get shiftsRegOver => 'Overage in the till.';

  @override
  String get shiftsRegister => 'Register';

  @override
  String get shiftsDate => 'Date';

  @override
  String get shiftsCashier => 'Cashier';

  @override
  String get shiftsOpenedAt => 'Opened at';

  @override
  String get shiftsOpeningFund => 'Opening cash';

  @override
  String get shiftsPin => 'Cashier PIN';

  @override
  String get shiftsExpectedPlaceholder => 'calculating…';

  @override
  String get shiftsCountedHelper =>
      'Pre-filled with the expected balance for matching.';

  @override
  String get shiftsCloseAction => 'Close till';

  @override
  String get salesHistoryTitle => 'Sales history';

  @override
  String get saleDetailTitle => 'Sale details';

  @override
  String get saleVoidTitle => 'Void sale';

  @override
  String get reportsTitle => 'Inventory report';

  @override
  String get reportsStoreName => 'Store name';

  @override
  String get reportsGenerate => 'Generate PDF report';

  @override
  String get reportsSave => 'Save';

  @override
  String get reportsShare => 'Share';

  @override
  String get reportsPrint => 'Print';

  @override
  String get reportsProducts => 'Products';

  @override
  String get reportsUnits => 'Units';

  @override
  String get reportsLowStock => 'Low stock';

  @override
  String get reportsHint => 'Generate the report to see it on screen.';

  @override
  String get reportsErrorGenerate => 'Could not generate the report';

  @override
  String get reportsErrorSave => 'Could not save the report';

  @override
  String get reportsErrorShare => 'Error sharing the report';

  @override
  String reportsSavedAt(String path) {
    return 'Saved at:\n$path';
  }

  @override
  String get scannerEntrada => 'In';

  @override
  String get scannerSalida => 'Out';

  @override
  String get scannerScanCode => 'Scan barcode';
}
