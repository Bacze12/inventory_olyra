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

  static const PdfPageFormat sheetFormat = PdfPageFormat(
    210 * PdfPageFormat.mm,
    297 * PdfPageFormat.mm,
    marginAll: 5 * PdfPageFormat.mm,
  );

  static const double _labelCellWidth = 58 * PdfPageFormat.mm;
  static const double _labelCellHeight = 40 * PdfPageFormat.mm;
  static const double _labelGap = 2.5 * PdfPageFormat.mm;

  /// Ordena los productos para imprimirlos en la hoja: por nombre sin
  /// distinguir mayúsculas y, si hay empate, por código de barras.
  static List<Product> orderForSheet(List<Product> products) {
    final ordered = List<Product>.from(products);
    ordered.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.barcode.compareTo(b.barcode);
    });
    return ordered;
  }

  Future<Uint8List> buildLabelPdf(Product product) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: labelFormat,
        build: (context) => pw.Column(
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
        ),
      ),
    );
    return doc.save();
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

  pw.Widget _buildSheetLabel(Product product) {
    return pw.Container(
      width: _labelCellWidth,
      height: _labelCellHeight,
      child: pw.Column(
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
          pw.SizedBox(height: 3),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: product.barcode,
            width: 52 * PdfPageFormat.mm,
            height: 18 * PdfPageFormat.mm,
            drawText: true,
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Cantidad: ${product.quantity}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Mín: ${product.minStock}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Genera un PDF con las etiquetas de todos los [products] ordenados en la
  /// hoja (A4), distribuyéndolas varias por página.
  Future<Uint8List> buildAllLabelsPdf(List<Product> products) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: sheetFormat,
        build: (context) => [
          pw.Wrap(
            spacing: _labelGap,
            runSpacing: _labelGap,
            children: [
              for (final product in orderForSheet(products))
                _buildSheetLabel(product),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> printAllLabels(List<Product> products) async {
    if (products.isEmpty) return;
    await Printing.layoutPdf(
      onLayout: (format) => buildAllLabelsPdf(products),
      format: sheetFormat,
      usePrinterSettings: true,
      dynamicLayout: true,
      name: 'etiquetas_totales',
    );
  }
}