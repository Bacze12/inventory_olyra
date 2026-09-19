import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/settings/language_provider.dart';

void main() {
  late SettingsRepository repository;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('scanflow_language_test_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    repository = SettingsRepository(AppDatabase.instance);
    final db = await AppDatabase.instance.database;
    await db.delete('settings');
  });

  test('por defecto el idioma es español', () async {
    final provider = LanguageProvider(repository);
    await provider.init();
    expect(provider.locale.languageCode, AppConstants.defaultLanguage);
  });

  test('setLanguage persiste la selección en settings', () async {
    final provider = LanguageProvider(repository);
    await provider.setLanguage('en');
    expect(provider.locale.languageCode, 'en');
    expect(await repository.get(AppConstants.settingLanguage), 'en');
  });

  test('init carga el idioma persistido al reiniciar', () async {
    await repository.set(AppConstants.settingLanguage, 'en');
    final provider = LanguageProvider(repository);
    await provider.init();
    expect(provider.locale.languageCode, 'en');
  });

  test('setLanguage notifica a los listeners al cambiarlo', () async {
    final provider = LanguageProvider(repository);
    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.setLanguage('en');
    expect(notifications, 1);
  });
}