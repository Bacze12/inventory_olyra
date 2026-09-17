import 'package:flutter/services.dart';

/// Destino de lecturas de la pistola láser HID (USB/Bluetooth que emula
/// teclado).
///
/// Cada pantalla que quiera recibir lecturas implementa este contrato y se
/// registra en [ScannerInputService] mientras está visible. El servicio enruta
/// cada [KeyEvent] a la pantalla superior registrada y **nunca navega por sí
/// mismo** (no dispara el POS): si no hay ningún sink, la lectura simplemente
/// se ignora.
abstract class ScannerInputSink {
  /// Recibe una tecla de la pistola HID. Debe devolver `true` si la consumió
  /// (detiene la propagación) o `false` para dejarla pasar al árbol normal de
  /// texto/atajos.
  bool handleGunKey(KeyEvent event);

  /// Limpia cualquier tira de caracteres a medio leer cuando el sink deja de
  /// estar en primer plano (evita procesar lecturas obsoletas al volver).
  void clearBuffer();
}

/// Servicio global de entrada para pistolas láser / lectores de código que
/// emulan teclado (HID).
///
/// Instalado una sola vez desde la pantalla inicial. Mantiene una pila de
/// [ScannerInputSink]; la tecla de la pistola se entrega SOLO al sink superior
/// (la pantalla visible). Al abrirse/cerrarse una pantalla que consume lecturas,
/// los búferes de todas las demás se limpian para no arrastrar ruido.
class ScannerInputService {
  ScannerInputService._();

  /// Instancia única de la app.
  static final ScannerInputService instance = ScannerInputService._();

  final List<ScannerInputSink> _sinks = [];
  bool _installed = false;

  /// Instala el handler global de teclado (idempotente).
  void install() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_route);
  }

  /// Coloca [sink] como destino superior (la pantalla visible).
  void register(ScannerInputSink sink) {
    _sinks.remove(sink);
    _sinks.add(sink);
    _clearAllBuffers();
  }

  /// Quita [sink] y restaura el que quedaba debajo (si existe).
  void unregister(ScannerInputSink sink) {
    _sinks.remove(sink);
    _clearAllBuffers();
  }

  bool get hasActiveSink => _sinks.isNotEmpty;

  void _clearAllBuffers() {
    for (final sink in _sinks) {
      sink.clearBuffer();
    }
  }

  /// Router: entrega el evento al sink superior y propaga su resultado.
  bool _route(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_sinks.isEmpty) return false; // Sin consumidor: no hacer nada.
    return _sinks.last.handleGunKey(event);
  }
}