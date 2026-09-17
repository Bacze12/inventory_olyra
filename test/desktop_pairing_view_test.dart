import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scanflow/data/services/pairing_service.dart';
import 'package:scanflow/views/pairing/desktop_pairing_view.dart';

class _FakeSettings implements PairingSettingsSource {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _FakeSecrets implements PairingSecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  Future<PairingService> buildService() async {
    return PairingService(
      settings: _FakeSettings(),
      secrets: _FakeSecrets(),
    );
  }

  group('DesktopPairingView', () {
    testWidgets('muestra QR, PIN y estado de espera', (tester) async {
      final service = await buildService();
      await tester.pumpWidget(
        MaterialApp(home: DesktopPairingView(service: service)),
      );

      // Deja que la sesión asíncrona se resuelva.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('pairing_qr')), findsOneWidget);

      final pinText = tester.widget<Text>(
        find.byKey(const ValueKey('pairing_pin')),
      );
      expect(RegExp(r'^\d{6}$').hasMatch(pinText.data!), isTrue);

      expect(find.textContaining('Esperando conexión del teléfono'), findsOneWidget);
      expect(find.text('Confirmar manualmente'), findsOneWidget);

      // Desmonta para cancelar los timers de espera/contador regresivo.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('la confirmación manual muestra la pantalla vinculada',
        (tester) async {
      final service = await buildService();
      await tester.pumpWidget(
        MaterialApp(home: DesktopPairingView(service: service)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.ensureVisible(find.text('Confirmar manualmente'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Confirmar manualmente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Dispositivo vinculado'), findsOneWidget);
      expect(find.textContaining('Tienda'), findsWidgets);
      expect(find.text('Desvincular'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('desvincula y vuelve a generar un código', (tester) async {
      final service = await buildService();
      await tester.pumpWidget(
        MaterialApp(home: DesktopPairingView(service: service)),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.ensureVisible(find.text('Confirmar manualmente'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Confirmar manualmente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.ensureVisible(find.text('Desvincular'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Desvincular'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Diálogo de confirmación (FilledButton con la misma etiqueta).
      await tester.tap(find.widgetWithText(FilledButton, 'Desvincular'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Vuelve a la espera con un nuevo QR/PIN.
      expect(find.byKey(const ValueKey('pairing_qr')), findsOneWidget);
      expect(find.textContaining('Esperando conexión del teléfono'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}