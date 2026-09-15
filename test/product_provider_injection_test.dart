import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/core/config/olyra_config.dart';
import 'package:scanflow/core/utils/formatters.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/remote/olyra_license_api.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/features/activation/license_credential_store.dart';
import 'package:scanflow/features/activation/olyra_license_controller.dart';
import 'package:scanflow/features/products/product_provider.dart';
import 'package:scanflow/services/hardware_id_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Product _draft(String barcode) {
  final now = nowIso();
  return Product(
    name: 'Guardado con controller inyectado',
    barcode: barcode,
    quantity: 2,
    minStock: 1,
    price: 500,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir =
        Directory.systemTemp.createTempSync('scanflow_inject_save_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  test(
      'save() con OlyraLicenseController inyectado (sin init) no lanza '
      'ProviderNotFoundError y persiste', () async {
    final repository = ProductRepository(AppDatabase.instance);
    // OlyraLicenseController se construye pero NO se inicializa: `claims`
    // queda null y ningún código lee del contexto de Provider.
    final license = OlyraLicenseController(
      hardware: HardwareIdService(const FlutterSecureStorage()),
      api: OlyraLicenseApi(
        activationUrl: OlyraConfig.activationUrl,
        validateUrl: OlyraConfig.validateUrl,
      ),
      credentials: LicenseCredentialStore(const FlutterSecureStorage()),
      publicKeyPem: OlyraConfig.publicKeyPem,
    );
    final provider = ProductProvider(repository, license);

    final barcode = '01987654321001';
    final error = await provider.save(_draft(barcode));
    expect(error, isNull, reason: error);

    final saved = await repository.byBarcode(barcode);
    expect(saved, isNotNull);
    expect(saved!.quantity, 2);
    expect(saved.userAppId, isNull); // claims null → sin user_app_id.
  });

  test('save() sin controller (argumento opcional) sigue funcionando',
      () async {
    final repository = ProductRepository(AppDatabase.instance);
    final provider = ProductProvider(repository);

    final barcode = '01987654321002';
    final error = await provider.save(_draft(barcode));
    expect(error, isNull, reason: error);
    expect(await repository.byBarcode(barcode), isNotNull);
  });
}