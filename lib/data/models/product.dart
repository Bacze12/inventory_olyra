class Product {
  const Product({
    this.id,
    required this.name,
    required this.barcode,
    required this.quantity,
    required this.minStock,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String barcode;
  final int quantity;
  final int minStock;
  final String createdAt;
  final String updatedAt;

  bool get isLowStock => quantity <= minStock;

  int get neededUnits => quantity < minStock ? minStock - quantity : 0;

  factory Product.fromMap(Map<String, Object?> map) => Product(
        id: map['id'] as int?,
        name: map['name'] as String,
        barcode: map['barcode'] as String,
        quantity: map['quantity'] as int,
        minStock: map['min_stock'] as int,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'quantity': quantity,
        'min_stock': minStock,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    int? quantity,
    int? minStock,
    String? createdAt,
    String? updatedAt,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        quantity: quantity ?? this.quantity,
        minStock: minStock ?? this.minStock,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() => 'Product(${id ?? '-'}) $name [$barcode]';
}