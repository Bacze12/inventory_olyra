import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../data/models/product.dart';

class ThermalPrintService {
  const ThermalPrintService();

  Future<void> ensureBluetoothPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      final granted = statuses.values.any((status) => status.isGranted);
      if (!granted) {
        throw StateError('Permiso de Bluetooth no otorgado');
      }
    }
  }

  Future<List<BluetoothInfo>> listDevices() async {
    await ensureBluetoothPermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw StateError('Bluetooth apagado');
    }
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> printLabel(Product product, String macAddress) async {
    if (!await PrintBluetoothThermal.connect(macPrinterAddress: macAddress)) {
      throw StateError('No se pudo conectar a la impresora');
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);

    final command = <int>[
      ...generator.setGlobalCodeTable('cp1252'),
      ...generator.text(
        product.name,
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
        linesAfter: 1,
      ),
      ..._barcodeCommands(generator, product),
      ...generator.text(
        'Cantidad: ${product.quantity}   Min: ${product.minStock}',
        linesAfter: 2,
      ),
      ...generator.feed(2),
      ...generator.cut(),
    ];

    final ok = await PrintBluetoothThermal.writeBytes(command);
    await PrintBluetoothThermal.disconnect;
    return ok;
  }

  List<int> _barcodeCommands(Generator generator, Product product) {
    final code = product.barcode.trim();
    if (code.length < 2) {
      return generator.text('Codigo: $code');
    }
    return generator.barcode(
      Barcode.code128(code.split('')),
      width: 2,
      height: 70,
      textPos: BarcodeText.below,
    );
  }
}