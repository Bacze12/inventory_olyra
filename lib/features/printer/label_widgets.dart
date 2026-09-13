import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/product.dart';

/// Tamaños de etiqueta térmica soportados (ancho típico 50/57–58 mm).
enum ThermalLabelSize {
  /// Etiqueta 58 × 40 mm (papel continuo de 58 mm).
  label58x40,

  /// Etiqueta 50 × 30 mm.
  label50x30,
}

extension ThermalLabelSizeX on ThermalLabelSize {
  String get label {
    switch (this) {
      case ThermalLabelSize.label58x40:
        return '58 × 40 mm';
      case ThermalLabelSize.label50x30:
        return '50 × 30 mm';
    }
  }

  PdfPageFormat get pageFormat {
    switch (this) {
      case ThermalLabelSize.label58x40:
        return PdfPageFormat(
          58 * PdfPageFormat.mm,
          40 * PdfPageFormat.mm,
          marginAll: 2 * PdfPageFormat.mm,
        );
      case ThermalLabelSize.label50x30:
        return PdfPageFormat(
          50 * PdfPageFormat.mm,
          30 * PdfPageFormat.mm,
          marginAll: 2 * PdfPageFormat.mm,
        );
    }
  }
}

/// Dibuja una etiqueta térmica (una por página) con nombre, código de barras
/// Code128 y stock mínimo, ajustada al [format] indicado.
pw.Widget buildThermalLabel(Product product, {required PdfPageFormat format}) {
  final availableHeight = format.availableHeight;
  final compact = availableHeight <= 26 * PdfPageFormat.mm;
  final nameSize = compact ? 9.0 : 11.0;
  final metaSize = compact ? 7.5 : 9.0;
  final barcodeHeight = (compact ? 11.0 : 16.0) * PdfPageFormat.mm;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        product.name,
        maxLines: compact ? 1 : 2,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: nameSize,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: compact ? 1.5 : 3),
      pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: product.barcode,
          width: format.availableWidth,
          height: barcodeHeight,
          drawText: true,
        ),
      ),
      pw.SizedBox(height: compact ? 1 : 2),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Cant: ${product.quantity}',
            style: pw.TextStyle(fontSize: metaSize),
          ),
          pw.Text(
            'Mín: ${product.minStock}',
            style: pw.TextStyle(fontSize: metaSize),
          ),
          pw.Text(
            '\$${product.price.toStringAsFixed(0)}',
            style: pw.TextStyle(fontSize: metaSize),
          ),
        ],
      ),
    ],
  );
}