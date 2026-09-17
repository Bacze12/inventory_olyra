import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/utils/formatters.dart';
import 'scanner_input_service.dart';

/// Redirección global de lecturas de la pistola HID fuera del flujo de ventas.
///
/// Registrado una sola vez desde la pantalla principal como sink de respaldo:
/// mientras el POS o un formulario de producto estén abiertos, ellos reciben
/// las lecturas (labores de venta/edición). Cuando NO hay ninguna pantalla que
/// consuma lecturas (gestión de inventario, listados, Home), este sink captura
/// el código completo (tira rápida + Enter) y lo redirige a la pantalla de
/// "Registrar / Editar Producto".
///
/// No interfiere con la escritura normal: si un campo de texto tiene el foco
/// (p. ej. buscador), los caracteres pasan al árbol normal y aquí no se captura
/// nada.
class GlobalGunRedirect implements ScannerInputSink {
  GlobalGunRedirect(this.onComplete);

  /// Recibe el código completo leído (normalizado). Debe navegar a la ficha
  /// del producto (existente → editar; inexistente → nuevo producto).
  final void Function(String code) onComplete;

  final StringBuffer _buffer = StringBuffer();

  /// Máximo de caracteres acumulables antes del Enter (evita buffers locos si
  /// la pistola quedara pegada o llega texto largo).
  static const int _maxLen = 64;

  bool get _isEditableFocused {
    final focus = FocusManager.instance.primaryFocus;
    return focus?.context?.widget is EditableText;
  }

  @override
  bool handleGunKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Campo de texto con foco: se deja pasar (el usuario puede estar
    // escribiendo en un buscador). El POS/vista de ventas usa sus propios
    // sinks cuando está visible.
    if (_isEditableFocused) return false;

    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;

    if (isEnter) {
      final raw = _buffer.toString();
      _buffer.clear();
      final code = normalizeBarcode(raw);
      if (code.isEmpty) return false;
      onComplete(code);
      return true;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && _buffer.length < _maxLen) {
      _buffer.write(char);
    }
    return false;
  }

  @override
  void clearBuffer() => _buffer.clear();
}