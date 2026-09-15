import 'dart:io' show HttpClient;

import 'package:http/http.dart' as http;

/// Cliente HTTP que sigue redirecciones 307/308 (y 301/302/303) **conservando
/// método y body** del POST original, en lugar de delegar en el auto-follow del
/// cliente HTTP que en algunos casos pierde el body o lee la URL final.
///
/// - 307/308 y 301/302: se reenvía el POST tal cual contra `Location`.
/// - 303: pasa a GET sin body (semántica del código 303).
/// - Sin `Location`, otros 3xx o agotar [maxRedirects]: se devuelve la
///   respuesta como final (el caller la tratará como error si no es 200).
/// - Drena los cuerpos de las respuestas intermedias para no saturar la
///   conexión del `HttpClient` de I/O.
class OlyraRedirectClient extends http.BaseClient {
  OlyraRedirectClient({http.Client? inner}) : _inner = inner ?? NoFollowIOClient();

  static const int maxRedirects = 3;

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    var method = request.method;
    var url = request.url;
    final headers = Map<String, String>.from(request.headers);

    for (var hop = 0;; hop++) {
      final req = http.Request(method, url)..headers.addAll(headers);
      if (method != 'GET' && method != 'HEAD') {
        req.bodyBytes = bodyBytes;
      }

      final response = await _inner.send(req);
      final status = response.statusCode;
      final location = response.headers['location'];

      if (hop >= maxRedirects ||
          location == null ||
          (status != 301 &&
              status != 302 &&
              status != 303 &&
              status != 307 &&
              status != 308)) {
        return response;
      }

      // Drena el body de la redirección para liberar el socket.
      await response.stream.drain<void>();

      url = url.resolveUri(Uri.parse(location));
      switch (status) {
        case 307:
        case 308:
        case 301:
        case 302:
          // Se conserva POST y su body (seguro para APIs de licencia/sync).
          break;
        case 303:
          method = 'GET';
          break;
      }
    }
  }

  @override
  void close() => _inner.close();
}

/// Transporte `dart:io` con `followRedirects = false` a nivel de request
/// (la API de I/O del SDK actual movió la propiedad al request). Con esto el
/// seguimiento de redirecciones queda 100% en manos de [OlyraRedirectClient],
/// que reconstruye el POST preservando el body en 307/308.
class NoFollowIOClient extends http.BaseClient {
  final HttpClient _io = HttpClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final ioRequest = await _io.openUrl(request.method, request.url);
    ioRequest.followRedirects = false;
    request.headers.forEach(ioRequest.headers.set);

    final bodyBytes = await request.finalize().toBytes();
    ioRequest.contentLength = bodyBytes.length;
    if (bodyBytes.isNotEmpty) {
      ioRequest.add(bodyBytes);
    }

    final ioResponse = await ioRequest.close();

    final headerMap = <String, String>{};
    ioResponse.headers.forEach((name, values) {
      if (values.isNotEmpty) headerMap[name] = values.first;
    });

    return http.StreamedResponse(
      ioResponse,
      ioResponse.statusCode,
      contentLength:
          ioResponse.contentLength == -1 ? null : ioResponse.contentLength,
      headers: headerMap,
      reasonPhrase: ioResponse.reasonPhrase,
      isRedirect: false,
      request: http.Request(request.method, request.url),
    );
  }

  @override
  void close() => _io.close(force: true);
}