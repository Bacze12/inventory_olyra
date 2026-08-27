import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/product.dart';

class PdfReportService {
  const PdfReportService();

  Future<Uint8List> build(
    PdfPageFormat format,
    List<Product> products, {
    String? storeName,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(18),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFE5F5EC),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: pw.Text(
                  storeName?.trim().isNotEmpty == true
                      ? storeName!.trim()
                      : AppConstants.defaultStoreName,
                  style: const pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
              ),
              pw.Text(
                formatDateTime(DateTime.now().toIso8601String()),
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Reporte de inventario',
            style: const pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '${products.length} productos en catálogo',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          _summary(products),
          pw.SizedBox(height: 14),
          pw.Text(
            'Existencias',
            style: const pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          _productsTable(products),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _summary(List<Product> products) {
    final totalUnits = products.fold<int>(0, (sum, p) => sum + p.quantity);
    final lowStock = products.where((p) => p.isLowStock).length;

    return pw.Row(
      children: [
        pw.Expanded(child: _statCard('Productos', '${products.length}')),
        pw.SizedBox(width: 8),
        pw.Expanded(child: _statCard('Unidades', '$totalUnits')),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _statCard(
            'Con stock bajo',
            '$lowStock',
            color: lowStock > 0
                ? const PdfColor.fromInt(0xFFFFEBEA)
                : null,
            textColor: lowStock > 0 ? const PdfColor.fromInt(0xFFB3261E) : null,
          ),
        ),
      ],
    );
  }

  pw.Widget _statCard(
    String label,
    String value, {
    PdfColor? color,
    PdfColor? textColor,
  }) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: pw.BoxDecoration(
          color: color ?? const PdfColor.fromInt(0xFFF3F4F6),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: textColor ?? PdfColors.grey900,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      );

  pw.Widget _productsTable(List<Product> products) {
    if (products.isEmpty) {
      return pw.Text(
        'No hay productos registrados.',
        style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
      );
    }

    return pw.Table(
      border: const pw.TableBorder(
        top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.6),
        2: pw.FlexColumnWidth(0.9),
        3: pw.FlexColumnWidth(0.9),
        4: pw.FlexColumnWidth(1.0),
      },
      children: [
        _headerRow(),
        for (final product in products) _productRow(product),
      ],
    );
  }

  pw.TableRow _headerRow() => pw.TableRow(
        decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFE5F5EC)),
        children: [_headerCell('Producto'), _headerCell('Código'),
          _headerCell('Cant.', center: true), _headerCell('Mín.', center: true),
          _headerCell('Estado', center: true)],
      );

  pw.Widget _headerCell(String text, {bool center = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: pw.Text(
          text,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.green900,
          ),
        ),
      );

  pw.TableRow _productRow(Product product) {
    final low = product.isLowStock;
    return pw.TableRow(
      decoration: low
          ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFFEBEA))
          : null,
      children: [
        _cell(product.name),
        _cell(product.barcode),
        _cell('${product.quantity}', center: true),
        _cell('${product.minStock}', center: true),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          alignment: pw.Alignment.center,
          child: pw.Text(
            low ? 'BAJO' : 'OK',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: low
                  ? const PdfColor.fromInt(0xFFB3261E)
                  : PdfColors.green700,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _cell(String text, {bool center = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: pw.Text(
          text,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          style: const pw.TextStyle(fontSize: 9),
        ),
      );
}