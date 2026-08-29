class Product {
  const Product({
    this.id,
    required this.name,
    required this.barcode,
    required this.quantity,
    required this.minStock,
    this.price = 0.0,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String barcode;
  final int quantity;
  final int minStock;
  final double price;
  final String? imagePath;
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
        price: (map['price'] as num?)?.toDouble() ?? 0.0,
        imagePath: map['image_path'] as String?,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'quantity': quantity,
        'min_stock': minStock,
        'price': price,
        'image_path': imagePath,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    int? quantity,
    int? minStock,
    double? price,
    String? imagePath,
    String? createdAt,
    String? updatedAt,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        quantity: quantity ?? this.quantity,
        minStock: minStock ?? this.minStock,
        price: price ?? this.price,
        imagePath: imagePath ?? this.imagePath,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() => 'Product(${id ?? '-'}) $name [$barcode]';
}