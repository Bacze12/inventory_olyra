import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/models/product.dart';
import 'label_widgets.dart';

/// Producto y número de copias a imprimir en la cola de etiquetas.
class MassLabelItem {
  const MassLabelItem({required this.product, required this.copies});

  final Product product;
  final int copies;
}

/// Impresión masiva de etiquetas térmicas: genera un PDF unificado (una
/// página por etiqueta, 58×40 o 50×30 mm) listo para la impresora
/// predeterminada de Windows.
class MassLabelPrintService {
  const MassLabelPrintService();

  /// Expande los ítems en la cola real de etiquetas (skippea copias <= 0).
  int totalLabels(List<MassLabelItem> items) {
    var total = 0;
    for (final item in items) {
      total += item.copies > 0 ? item.copies : 0;
    }
    return total;
  }

  Future<Uint8List> buildMassLabelPdf(
    List<MassLabelItem> items,
    ThermalLabelSize size,
  ) async {
    final format = size.pageFormat;
    final doc = pw.Document();

    for (final item in items) {
      for (var i = 0; i < item.copies; i++) {
        doc.addPage(
          pw.Page(
            pageFormat: format,
            build: (_) => buildThermalLabel(item.product, format: format),
          ),
        );
      }
    }
    return doc.save();
  }

  /// Envía el PDF a la impresión (diálogo de Windows con la impresora
  /// predeterminada preseleccionada).
  Future<bool> printLabels(
    List<MassLabelItem> items,
    ThermalLabelSize size,
  ) {
    return Printing.layoutPdf(
      onLayout: (_) => buildMassLabelPdf(items, size),
      format: size.pageFormat,
      dynamicLayout: false,
      usePrinterSettings: false,
      name: 'etiquetas_masivas',
    );
  }

  /// Guarda el PDF (o lo comparte) como archivo.
  Future<bool> savePdf(
    List<MassLabelItem> items,
    ThermalLabelSize size,
  ) async {
    final bytes = await buildMassLabelPdf(items, size);
    return Printing.sharePdf(
      bytes: bytes,
      filename: 'etiquetas_masivas.pdf',
    );
  }
}