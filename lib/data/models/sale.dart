enum PaymentMethod {
  efectivo('Efectivo'),
  tarjeta('Tarjeta');

  const PaymentMethod(this.label);

  final String label;

  String get dbValue => label;

  static PaymentMethod fromDb(String value) => value == 'Tarjeta'
      ? PaymentMethod.tarjeta
      : PaymentMethod.efectivo;
}

enum SaleStatus {
  completada('Completada'),
  anulada('Anulada');

  const SaleStatus(this.label);

  final String label;

  String get dbValue => label;

  static SaleStatus fromDb(String value) => value == 'Anulada'
      ? SaleStatus.anulada
      : SaleStatus.completada;
}

/// Una venta registrada en el POS (cabecera).
class Sale {
  const Sale({
    this.id,
    required this.paymentMethod,
    required this.subtotal,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    this.received,
    required this.change,
    required this.status,
    required this.createdAt,
    this.items = const [],
  });

  final int? id;
  final PaymentMethod paymentMethod;
  final double subtotal;
  final double taxRate;
  final double taxAmount;
  final double total;
  final double? received;
  final double change;
  final SaleStatus status;
  final String createdAt;
  final List<SaleItem> items;

  bool get canBeAnnulled => status == SaleStatus.completada;

  /// Folio legible, ej. `#0042`.
  String get folio => '#${(id ?? 0).toString().padLeft(4, '0')}';

  factory Sale.fromMap(Map<String, Object?> map) => Sale(
        id: map['id'] as int?,
        paymentMethod: PaymentMethod.fromDb(map['payment_method'] as String),
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
        taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0.0,
        taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0.0,
        total: (map['total'] as num?)?.toDouble() ?? 0.0,
        received: (map['received'] as num?)?.toDouble(),
        change: (map['change'] as num?)?.toDouble() ?? 0.0,
        status: SaleStatus.fromDb(map['status'] as String),
        createdAt: map['created_at'] as String,
      );

  Sale copyWith({List<SaleItem>? items, SaleStatus? status}) => Sale(
        id: id,
        paymentMethod: paymentMethod,
        subtotal: subtotal,
        taxRate: taxRate,
        taxAmount: taxAmount,
        total: total,
        received: received,
        change: change,
        status: status ?? this.status,
        createdAt: createdAt,
        items: items ?? this.items,
      );
}

/// Línea del ticket: snapshot del producto vendido.
class SaleItem {
  const SaleItem({
    this.id,
    this.saleId,
    required this.productId,
    required this.productName,
    required this.barcode,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
  });

  final int? id;
  final int? saleId;
  final int? productId;
  final String productName;
  final String? barcode;
  final double unitPrice;
  final int quantity;
  final double subtotal;

  factory SaleItem.fromMap(Map<String, Object?> map) => SaleItem(
        id: map['id'] as int?,
        saleId: map['sale_id'] as int?,
        productId: map['product_id'] as int?,
        productName: map['product_name'] as String,
        barcode: map['barcode'] as String?,
        unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
        quantity: map['quantity'] as int,
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      );
}