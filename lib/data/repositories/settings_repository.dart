import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class SettingsRepository {
  const SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final db = await _db.database;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<String> getOr(String key, String fallback) async {
    final value = await get(key);
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  Future<void> set(String key, String value) async {
    final db = await _db.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}