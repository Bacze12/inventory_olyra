import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:scanflow/data/services/pairing_service.dart';

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

class _FakeHttp extends http.BaseClient {
  _FakeHttp({this.statusCode = 404, this.body = ''});

  int statusCode = 404;
  String body = '';
  int getCalls = 0;
  int postCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET') getCalls++;
    if (request.method == 'POST') postCalls++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _Harness {
  _Harness({_FakeHttp? http})
      : settings = _FakeSettings(),
        secrets = _FakeSecrets(),
        httpClient = http ?? _FakeHttp();

  final _FakeSettings settings;
  final _FakeSecrets secrets;
  final _FakeHttp httpClient;

  PairingService get service => PairingService(
        settings: settings,
        secrets: secrets,
        httpClient: httpClient,
      );
}

void main() {
  group('PairingService - sesión y payload', () {
    test('startSession genera PIN de 6 dígitos y tenant por defecto', () async {
      final harness = _Harness();
      final session = await harness.service.startSession();

      expect(RegExp(r'^\d{6}$').hasMatch(session.pairCode), isTrue);
      expect(session.tenantId, startsWith('STORE_'));
      expect(session.isExpired, isFalse);
    });

    test('resolveTenantId persiste y reutiliza la tienda', () async {
      final harness = _Harness();
      final first = await harness.service.resolveTenantId();
      final second = await harness.service.resolveTenantId();
      expect(first, second);
      expect(harness.settings.values[PairingService.kTenantKey], first);
    });

    test('encodePayload genera JSON con la forma esperada', () async {
      final harness = _Harness();
      final session = await harness.service.startSession();
      final raw = harness.service.encodePayload(session);

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['tenant_id'], session.tenantId);
      expect(decoded['pair_code'], session.pairCode);
      expect(decoded['expires_at'] is int, isTrue);
    });

    test('parsePayload devuelve payload idéntico al codificado', () async {
      final harness = _Harness();
      final session = await harness.service.startSession();
      final payload = harness.service.parsePayload(
        harness.service.encodePayload(session),
      );

      expect(payload, isNotNull);
      expect(payload!.tenantId, session.tenantId);
      expect(payload.pairCode, session.pairCode);
      expect(payload.expiresAt.millisecondsSinceEpoch,
          session.expiresAt.millisecondsSinceEpoch);
    });

    test('parsePayload acepta un JSON manual válido', () async {
      final harness = _Harness();
      final expires = DateTime.now().add(const Duration(minutes: 5));
      final raw = jsonEncode({
        'tenant_id': 'STORE_123',
        'pair_code': '482910',
        'expires_at': expires.millisecondsSinceEpoch,
      });

      final payload = harness.service.parsePayload(raw);

      expect(payload, isNotNull);
      expect(payload!.tenantId, 'STORE_123');
      expect(payload.pairCode, '482910');
      expect(payload.isExpired, isFalse);
    });

    test('parsePayload rechaza entradas inválidas', () async {
      final harness = _Harness();
      const base = {
        'tenant_id': 'STORE_123',
        'pair_code': '482910',
        'expires_at': 0,
      };

      expect(harness.service.parsePayload('no soy json'), isNull);
      expect(harness.service.parsePayload('   '), isNull);
      expect(
        harness.service.parsePayload(jsonEncode({'foo': 'bar'})),
        isNull,
      );
      expect(
        harness.service.parsePayload(jsonEncode({...base, 'tenant_id': ''})),
        isNull,
      );
      expect(
        harness.service.parsePayload(jsonEncode({...base, 'pair_code': '12'})),
        isNull,
      );
      expect(
        harness.service.parsePayload(
          jsonEncode({
            'tenant_id': 'STORE_123',
            'pair_code': '482910',
            'expires_at': DateTime.now().subtract(const Duration(seconds: 1))
                .millisecondsSinceEpoch,
          }),
        ),
        isNot(isNull),
      );
      final expired = harness.service.parsePayload(
        jsonEncode({
          'tenant_id': 'STORE_123',
          'pair_code': '482910',
          'expires_at': DateTime.now().subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        }),
      );
      expect(expired!.isExpired, isTrue);
    });
  });

  group('PairingService - credenciales', () {
    test('deviceToken es estable entre llamadas', () async {
      final harness = _Harness();
      final first = await harness.service.deviceToken();
      final second = await harness.service.deviceToken();
      expect(first, second);
      expect(second, startsWith('dvt_'));
    });

    test('sin servidor la vinculación se guarda de forma local', () async {
      final harness = _Harness();
      final payload = PairPayload(
        tenantId: 'STORE_123',
        pairCode: '482910',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      final outcome = await harness.service.linkWithPayload(payload);

      expect(outcome, PairingOutcome.ok);
      final creds = await harness.service.credentials();
      expect(creds, isNotNull);
      expect(creds!.tenantId, 'STORE_123');
      expect(creds.deviceToken, startsWith('dvt_'));
      expect(await harness.service.isPaired, isTrue);
      expect(harness.httpClient.postCalls, 0);
    });

    test('payload expirado no vincula', () async {
      final harness = _Harness();
      final payload = PairPayload(
        tenantId: 'STORE_123',
        pairCode: '482910',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );

      final outcome = await harness.service.linkWithPayload(payload);

      expect(outcome, PairingOutcome.expired);
      expect(await harness.service.isPaired, isFalse);
    });

    test('fallo del relay no guarda credenciales', () async {
      final httpClient = _FakeHttp(statusCode: 500, body: '{}');
      final harness = _Harness(http: httpClient);
      harness.settings.values[PairingService.kServerUrlKey] = 'http://relay';
      final payload = PairPayload(
        tenantId: 'STORE_123',
        pairCode: '482910',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      final outcome = await harness.service.linkWithPayload(payload);

      expect(outcome, PairingOutcome.sendFailed);
      expect(await harness.service.isPaired, isFalse);
      expect(httpClient.postCalls, 1);
    });

    test('relay confirma y guarda credenciales', () async {
      final httpClient = _FakeHttp(
        statusCode: 200,
        body: jsonEncode({'tenant_id': 'STORE_123', 'device_token': 'x'}),
      );
      final harness = _Harness(http: httpClient);
      harness.settings.values[PairingService.kServerUrlKey] = 'http://relay';
      final expectedToken = await harness.service.deviceToken();
      final payload = PairPayload(
        tenantId: 'STORE_123',
        pairCode: '482910',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      final outcome = await harness.service.linkWithPayload(payload);

      expect(outcome, PairingOutcome.ok);
      final creds = await harness.service.credentials();
      expect(creds!.deviceToken, expectedToken);
      expect(creds.tenantId, 'STORE_123');
      expect(httpClient.postCalls, 1);
    });

    test('unlink elimina la vinculación pero conserva el token', () async {
      final harness = _Harness();
      await harness.service.confirmManually(
        await harness.service.startSession(),
      );
      final tokenBefore = await harness.service.deviceToken();

      await harness.service.unlink();

      expect(await harness.service.credentials(), isNull);
      expect(await harness.service.isPaired, isFalse);
      expect(await harness.service.deviceToken(), tokenBefore);
    });
  });

  group('PairingService - comprobación en PC', () {
    test('sesión expirada devuelve expired', () async {
      final harness = _Harness();
      final session = await harness.service.startSession(
        ttl: const Duration(milliseconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final result = await harness.service.checkPairing(session);

      expect(result.expired, isTrue);
      expect(result.confirmed, isFalse);
    });

    test('sin servidor permanece en espera', () async {
      final harness = _Harness();
      final session = await harness.service.startSession();

      final result = await harness.service.checkPairing(session);

      expect(result.expired, isFalse);
      expect(result.confirmed, isFalse);
    });

    test('relay confirmado guarda credenciales en la PC', () async {
      const token = 'dvt_phone_token';
      final httpClient = _FakeHttp(
        statusCode: 200,
        body: jsonEncode({
          'tenant_id': 'STORE_123',
          'device_token': token,
        }),
      );
      final harness = _Harness(http: httpClient);
      harness.settings.values[PairingService.kServerUrlKey] = 'http://relay';
      final session = await harness.service.startSession();

      final result = await harness.service.checkPairing(session);

      expect(result.confirmed, isTrue);
      expect(result.credentials!.deviceToken, token);
      expect((await harness.service.credentials())!.tenantId, 'STORE_123');
      expect(httpClient.getCalls, 1);
    });

    test('relay sin confirmación aún en espera', () async {
      final httpClient = _FakeHttp(statusCode: 404, body: '');
      final harness = _Harness(http: httpClient);
      harness.settings.values[PairingService.kServerUrlKey] = 'http://relay';
      final session = await harness.service.startSession();

      final result = await harness.service.checkPairing(session);

      expect(result.confirmed, isFalse);
      expect(result.expired, isFalse);
    });
  });

  group('PairingService - descubrimiento del servidor local', () {
    final future = DateTime.now().add(const Duration(minutes: 5));

    test('parsePayload acepta host y puerto de la PC', () async {
      final harness = _Harness();
      final raw = jsonEncode({
        'tenant_id': 'STORE_123',
        'pair_code': '482910',
        'expires_at': future.millisecondsSinceEpoch,
        'server_host': '192.168.1.50',
        'server_port': 8080,
      });

      final payload = harness.service.parsePayload(raw);

      expect(payload, isNotNull);
      expect(payload!.serverHost, '192.168.1.50');
      expect(payload.serverPort, 8080);
    });

    test('puerto fuera de rango se descarta', () async {
      final harness = _Harness();
      final raw = jsonEncode({
        'tenant_id': 'STORE_123',
        'pair_code': '482910',
        'expires_at': future.millisecondsSinceEpoch,
        'server_host': '192.168.1.50',
        'server_port': 99999,
      });

      final payload = harness.service.parsePayload(raw);

      expect(payload, isNotNull);
      expect(payload!.serverHost, '192.168.1.50');
      expect(payload.serverPort, isNull);
    });

    test('encodePayload incluye host cuando la sesión lo tiene', () async {
      final harness = _Harness();
      final session = PairingSession(
        tenantId: 'STORE_123',
        pairCode: '123456',
        expiresAt: future,
        serverHost: '192.168.1.50',
        serverPort: 8080,
      );

      final decoded =
          jsonDecode(harness.service.encodePayload(session)) as Map;

      expect(decoded['server_host'], '192.168.1.50');
      expect(decoded['server_port'], 8080);
    });

    test('al vincular por QR con host, el teléfono guarda la URL de sync',
        () async {
      final harness = _Harness();
      final payload = PairPayload(
        tenantId: 'STORE_123',
        pairCode: '482910',
        expiresAt: future,
        serverHost: '192.168.1.50',
        serverPort: 8080,
      );

      final outcome = await harness.service.linkWithPayload(payload);

      expect(outcome, PairingOutcome.ok);
      expect(
        await harness.service.syncServerUrl(),
        'http://192.168.1.50:8080',
      );
    });

    test('sin host en el QR no se configura servidor de sync', () async {
      final harness = _Harness();
      final payload = PairPayload(
        tenantId: 'STORE_123',
        pairCode: '482910',
        expiresAt: future,
      );

      await harness.service.linkWithPayload(payload);

      expect(await harness.service.syncServerUrl(), isNull);
    });
  });
}