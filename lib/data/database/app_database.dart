import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  static const int _version = 8;

  /// Nombre del archivo de la BD local. Se conserva para no perder los datos
  /// de instalaciones previas; solo cambia el directorio contenedor.
  static const String _dbFileName = 'inventory.db';

  /// Nombre público del archivo `.db` local (para localizarlo al respaldar).
  static String get databaseFileName => _dbFileName;

  /// Caja sembrada por la migración v7 ("Caja 1"). Es el valor de respaldo de
  /// la preferencia local `pos_register_id`.
  static const String kDefaultRegisterId = 'caja-1';

  static const String kSettingRegisterId = 'pos_register_id';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _open();
    return _database!;
  }

  /// Resuelve el directorio contenedor de la BD.
  ///
  /// - Producción/instalada: `%APPDATA%\<App>\databases` vía path_provider,
  ///   creándolo explícitamente antes de `openDatabase`. sqflite_common_ffi usa
  ///   por defecto una ruta RELATIVA al CWD (`.dart_tool\...`), que en una
  ///   instalación arrancada con CWD no escribible provoca
  ///   `SqliteException(14): unable to open database file`.
  /// - Pruebas: sin path_provider disponible, honra el override de
  ///   `databaseFactoryFfi.setDatabasesPath(...)` usado por el harness.
  Future<_DatabaseDir> _ensureDatabaseDirectory() async {
    try {
      // Timeout de cortes: en pruebas sin path_provider (o con el directorio
      // de perfil bloqueado) esta llamada puede quedarse colgada; al fallar se
      // cae al override de sqflite (setDatabasesPath del harness o la ruta
      // por defecto del factory).
      final support = await getApplicationSupportDirectory()
          .timeout(const Duration(seconds: 10));
      final folder = Directory(join(support.path, 'databases'));
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      return _DatabaseDir(folder.path, isAppSupport: true);
    } catch (_) {
      final folder = Directory(await getDatabasesPath());
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      return _DatabaseDir(folder.path, isAppSupport: false);
    }
  }

  /// Un solo traslado, desde la ruta relativa antigua de sqflite_common_ffi
  /// (`<CWD>\.dart_tool\sqflite_common_ffi\databases`) hacia el nuevo
  /// contenedor de `%APPDATA%`, para que las instalaciones existentes de
  /// v1.3.x conserven su catálogo y ventas. Best-effort y solo si el destino
  /// aún no existe.
  Future<void> _migrateLegacyDatabase(String newPath) async {
    final target = File(newPath);
    if (await target.exists()) return;

    final legacy = File(join(
      Directory.current.path,
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      _dbFileName,
    ));
    try {
      if (await legacy.exists()) {
        await target.parent.create(recursive: true);
        await legacy.copy(newPath);
        debugPrint(
            '[AppDatabase] BD migrada desde la ruta relativa antigua a '
            '$newPath');
      }
    } catch (error) {
      debugPrint('[AppDatabase] no se pudo migrar la BD legada: $error');
    }
  }

  Future<Database> _open() async {
    final dir = await _ensureDatabaseDirectory();
    final path = join(dir.path, _dbFileName);
    if (dir.isAppSupport) {
      await _migrateLegacyDatabase(path);
    }
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
      // Cuenta (user_app_id) a la que pertenece cada producto. Alinea el
      // catálogo local con `pos_products` de la nube: cada bodega/entitlement
      // tiene su propio set de códigos. Nullable para instalaciones existentes.
      await db.execute('ALTER TABLE products ADD COLUMN user_app_id TEXT');
      await db.execute(
          'CREATE INDEX idx_products_scope ON products(user_app_id)');
    }
    if (oldVersion < 7) {
      // Módulo Turnos y Cajas: cajas (registers), cajeros (cashiers) y turnos
      // (pos_shifts). `sales.shift_id` vincula cada venta a su turno activo.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pos_registers (
          id TEXT PRIMARY KEY,
          user_app_id TEXT,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pos_cashiers (
          id TEXT PRIMARY KEY,
          user_app_id TEXT,
          name TEXT NOT NULL,
          pin_hash TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'cajero',
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pos_shifts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          register_id TEXT NOT NULL,
          cashier_id TEXT,
          opening_amount REAL NOT NULL DEFAULT 0.0,
          closing_amount REAL,
          expected_amount REAL NOT NULL DEFAULT 0.0,
          status TEXT NOT NULL DEFAULT 'abierto'
            CHECK(status IN ('abierto', 'cerrado')),
          opened_at TEXT NOT NULL,
          closed_at TEXT,
          synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('CREATE INDEX idx_shifts_register ON pos_shifts(register_id)');
      await db.execute('ALTER TABLE sales ADD COLUMN shift_id TEXT');
      await db.execute('CREATE INDEX idx_sales_shift ON sales(shift_id)');
      await _seedDefaultRegister(db);
    }
    if (oldVersion < 8) {
      // Movimientos pendientes de respaldo: mismo patrón que ventas/turnos.
      // Antes de v8 `movements` no tenía marca y se reenviaba la réplica
      // completa (idempotente pero sin "está pendiente/enviado" local). Ahora
      // cada ciclo solo sube los `synced = 0` y los marca tras el 200.
      await db.execute(
          'ALTER TABLE movements ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_app_id TEXT,
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
    await db.execute('CREATE INDEX idx_products_scope ON products(user_app_id)');

    await db.execute('''
      CREATE TABLE movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('IN', 'OUT')),
        delta INTEGER NOT NULL,
        quantity_after INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
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
        device_token TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        stock_warning INTEGER NOT NULL DEFAULT 0,
        shift_id TEXT,
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

    // Módulo Turnos y Cajas.
    await db.execute('''
      CREATE TABLE pos_registers (
        id TEXT PRIMARY KEY,
        user_app_id TEXT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pos_cashiers (
        id TEXT PRIMARY KEY,
        user_app_id TEXT,
        name TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'cajero',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pos_shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        register_id TEXT NOT NULL,
        cashier_id TEXT,
        opening_amount REAL NOT NULL DEFAULT 0.0,
        closing_amount REAL,
        expected_amount REAL NOT NULL DEFAULT 0.0,
        status TEXT NOT NULL DEFAULT 'abierto'
          CHECK(status IN ('abierto', 'cerrado')),
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_shifts_register ON pos_shifts(register_id)');
    await _seedDefaultRegister(db);
  }

  /// Caja por defecto ("Caja 1", RFC: la preferencia local cae a este id si la
  /// app arranca sin turnos previos). Idempotente.
  Future<void> _seedDefaultRegister(Database db) async {
    await db.insert(
      'pos_registers',
      {
        'id': kDefaultRegisterId,
        'user_app_id': null,
        'name': 'Caja 1',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

/// Resultado de la resolución del directorio de la BD local.
class _DatabaseDir {
  const _DatabaseDir(this.path, {required this.isAppSupport});

  final String path;

  /// `true` cuando la ruta proviene de path_provider (producción), lo que
  /// habilita la migración de datos desde la ruta relativa antigua.
  final bool isAppSupport;
}