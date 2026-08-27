enum MovementType {
  entrada,
  salida;

  String get dbValue => this == MovementType.entrada ? 'IN' : 'OUT';

  static MovementType fromDb(String value) =>
      value == 'IN' ? MovementType.entrada : MovementType.salida;
}

class Movement {
  const Movement({
    this.id,
    required this.productId,
    required this.type,
    required this.delta,
    required this.quantityAfter,
    required this.createdAt,
  });

  final int? id;
  final int productId;
  final MovementType type;
  final int delta;
  final int quantityAfter;
  final String createdAt;

  factory Movement.fromMap(Map<String, Object?> map) => Movement(
        id: map['id'] as int?,
        productId: map['product_id'] as int,
        type: MovementType.fromDb(map['type'] as String),
        delta: map['delta'] as int,
        quantityAfter: map['quantity_after'] as int,
        createdAt: map['created_at'] as String,
      );
}