import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  static const int _version = 1;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _open();
    return _database!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'inventory.db');
    return openDatabase(
      path,
      version: _version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        barcode TEXT NOT NULL UNIQUE,
        quantity INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');

    await db.execute('''
      CREATE TABLE movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('IN', 'OUT')),
        delta INTEGER NOT NULL,
        quantity_after INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_movements_product ON movements(product_id)');
    await db.execute('CREATE INDEX idx_movements_created ON movements(created_at)');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }
}