import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/models/product.dart';

class LabelPrintService {
  const LabelPrintService();

  static const PdfPageFormat labelFormat = PdfPageFormat(
    58 * PdfPageFormat.mm,
    40 * PdfPageFormat.mm,
    marginAll: 2 * PdfPageFormat.mm,
  );

  Future<Uint8List> buildLabelPdf(Product product) {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(pageFormat: labelFormat, build: (context) => _buildLabel(product)),
    );
    return doc.save();
  }

  /// Genera un PDF con una página de etiqueta por cada producto indicado.
  Future<Uint8List> buildLabelsPdf(List<Product> products) {
    final doc = pw.Document();
    for (final product in products) {
      doc.addPage(
        pw.Page(
          pageFormat: labelFormat,
          build: (context) => _buildLabel(product),
        ),
      );
    }
    return doc.save();
  }

  pw.Widget _buildLabel(Product product) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          product.name,
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
          style: const pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: product.barcode,
          width: 52 * PdfPageFormat.mm,
          height: 18 * PdfPageFormat.mm,
          drawText: true,
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Cantidad: ${product.quantity}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Mín: ${product.minStock}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> printLabel(Product product) async {
    await Printing.layoutPdf(
      onLayout: (format) => buildLabelPdf(product),
      format: labelFormat,
      usePrinterSettings: false,
      dynamicLayout: false,
      name: 'etiqueta_${product.barcode}',
    );
  }
}