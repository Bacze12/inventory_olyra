import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  static const int _version = 6;

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
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE products ADD COLUMN price REAL NOT NULL DEFAULT 0.0');
      await db.execute(
          'ALTER TABLE products ADD COLUMN image_path TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE sales (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          payment_method TEXT NOT NULL DEFAULT 'Efectivo'
            CHECK(payment_method IN ('Efectivo', 'Tarjeta')),
          subtotal REAL NOT NULL DEFAULT 0.0,
          tax_rate REAL NOT NULL DEFAULT 0.0,
          tax_amount REAL NOT NULL DEFAULT 0.0,
          total REAL NOT NULL DEFAULT 0.0,
          received REAL,
          change REAL NOT NULL DEFAULT 0.0,
          status TEXT NOT NULL DEFAULT 'Completada'
            CHECK(status IN ('Completada', 'Anulada')),
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE sale_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          barcode TEXT,
          unit_price REAL NOT NULL DEFAULT 0.0,
          quantity INTEGER NOT NULL DEFAULT 1,
          subtotal REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_sales_created ON sales(created_at)');
      await db.execute('CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)');
    }
    if (oldVersion < 4) {
      // Sincronización con la PC: permite rastrear el origen y reenvío de
      // ventas entre dispositivos vinculados.
      await db.execute('ALTER TABLE sales ADD COLUMN device_token TEXT');
      await db.execute(
          'ALTER TABLE sales ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'CREATE INDEX idx_sales_device ON sales(device_token, created_at)');
    }
    if (oldVersion < 5) {
      // Venta remota aceptada aunque el stock local no alcanzó (offline first):
      // se marca para avisar en el historial sin bloquear la sincronización.
      await db.execute(
          'ALTER TABLE sales ADD COLUMN stock_warning INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 6) {
      // Arqueo de caja: turnos y movimientos manuales (ingresos/egresos).
      await db.execute('''
        CREATE TABLE cash_shifts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL UNIQUE,
          opened_at TEXT NOT NULL,
          closed_at TEXT,
          initial_amount REAL NOT NULL DEFAULT 0.0,
          declared_amount REAL,
          expected_amount REAL,
          difference REAL,
          status TEXT NOT NULL DEFAULT 'open'
            CHECK(status IN ('open', 'closed')),
          synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE cash_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shift_id INTEGER NOT NULL,
          type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
          amount REAL NOT NULL DEFAULT 0.0,
          description TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          FOREIGN KEY (shift_id) REFERENCES cash_shifts(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_cash_movements_shift ON cash_movements(shift_id)');

      // Recrear `sales`: (a) relajar el CHECK de payment_method para admitir
      // Débito/Transferencia, y (b) añadir `shift_id` opcional del turno de
      // caja. Se suelta primero `sale_items` (tabla hija) para poder eliminar
      // `sales` sin violar la FK con PRAGMA foreign_keys = ON.
      await db.execute('''
        CREATE TABLE sales_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          payment_method TEXT NOT NULL DEFAULT 'Efectivo',
          subtotal REAL NOT NULL DEFAULT 0.0,
          tax_rate REAL NOT NULL DEFAULT 0.0,
          tax_amount REAL NOT NULL DEFAULT 0.0,
          total REAL NOT NULL DEFAULT 0.0,
          received REAL,
          change REAL NOT NULL DEFAULT 0.0,
          status TEXT NOT NULL DEFAULT 'Completada'
            CHECK(status IN ('Completada', 'Anulada')),
          device_token TEXT,
          synced INTEGER NOT NULL DEFAULT 0,
          stock_warning INTEGER NOT NULL DEFAULT 0,
          shift_id INTEGER,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO sales_new (
          id, payment_method, subtotal, tax_rate, tax_amount, total, received,
          change, status, device_token, synced, stock_warning, created_at
        )
        SELECT id, payment_method, subtotal, tax_rate, tax_amount, total,
               received, change, status, device_token, synced, stock_warning,
               created_at
        FROM sales
      ''');
      await db.execute('DROP TABLE sale_items');
      await db.execute('DROP TABLE sales');
      await db.execute('ALTER TABLE sales_new RENAME TO sales');
      await db.execute('''
        CREATE TABLE sale_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          barcode TEXT,
          unit_price REAL NOT NULL DEFAULT 0.0,
          quantity INTEGER NOT NULL DEFAULT 1,
          subtotal REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_sales_created ON sales(created_at)');
      await db.execute(
          'CREATE INDEX idx_sales_device ON sales(device_token, created_at)');
      await db.execute('CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)');
      await db.execute('CREATE INDEX idx_sales_shift ON sales(shift_id)');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        barcode TEXT NOT NULL UNIQUE,
        quantity INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 0,
        price REAL NOT NULL DEFAULT 0.0,
        image_path TEXT,
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

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_method TEXT NOT NULL DEFAULT 'Efectivo',
        subtotal REAL NOT NULL DEFAULT 0.0,
        tax_rate REAL NOT NULL DEFAULT 0.0,
        tax_amount REAL NOT NULL DEFAULT 0.0,
        total REAL NOT NULL DEFAULT 0.0,
        received REAL,
        change REAL NOT NULL DEFAULT 0.0,
        status TEXT NOT NULL DEFAULT 'Completada'
          CHECK(status IN ('Completada', 'Anulada')),
        device_token TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        stock_warning INTEGER NOT NULL DEFAULT 0,
        shift_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_sales_created ON sales(created_at)');
    await db.execute(
        'CREATE INDEX idx_sales_device ON sales(device_token, created_at)');
    await db.execute('CREATE INDEX idx_sales_shift ON sales(shift_id)');

    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        barcode TEXT,
        unit_price REAL NOT NULL DEFAULT 0.0,
        quantity INTEGER NOT NULL DEFAULT 1,
        subtotal REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)');

    await db.execute('''
      CREATE TABLE cash_shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        initial_amount REAL NOT NULL DEFAULT 0.0,
        declared_amount REAL,
        expected_amount REAL,
        difference REAL,
        status TEXT NOT NULL DEFAULT 'open'
          CHECK(status IN ('open', 'closed')),
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE cash_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_id INTEGER NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
        amount REAL NOT NULL DEFAULT 0.0,
        description TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (shift_id) REFERENCES cash_shifts(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_cash_movements_shift ON cash_movements(shift_id)');
  }
}