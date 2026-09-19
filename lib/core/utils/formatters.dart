String formatDateTime(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  } catch (_) {
    return iso;
  }
}

String nowIso() => DateTime.now().toIso8601String();

String fileStamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

String normalizeBarcode(String raw) => raw.trim();

/// Clave canónica de un código para comparaciones internas (dedup).
/// Unifica variantes numéricas: UPC-A (12) e ITF-14 (14) → EAN-13 verificado.
/// Así, frames que alternan "0"-prefijo o dígito verificador distintos se
/// tratan como el mismo código.
String canonicalBarcode(String code) {
  final raw = code.trim();
  if (raw.isEmpty || !RegExp(r'^\d+$').hasMatch(raw)) return raw;
  if (raw.length == 12) return _renormalizeEan13('0$raw');
  if (raw.length == 14) return _renormalizeEan13(raw.substring(1));
  return _renormalizeEan13(raw);
}

/// Variantes de búsqueda para un código escaneado. Normaliza GTINs numéricos:
/// - UPC-A (12 dígitos) → EAN-13 (antepone '0' y corrige el check digit).
/// - EAN-13 (13 dígitos) → corrije el check digit y ofrece la variante UPC-A.
/// - ITF-14 (14 dígitos) → extrae el GTIN-13 (quita el dígito indicador).
List<String> barcodeLookupVariants(String code) {
  final raw = code.trim();
  final variants = <String>{raw};
  if (raw.isEmpty || !RegExp(r'^\d+$').hasMatch(raw)) {
    return variants.toList();
  }

  if (raw.length == 12) {
    variants.add(_renormalizeEan13('0$raw'));
  } else if (raw.length == 13) {
    variants.add(_renormalizeEan13(raw));
    if (raw.startsWith('0')) variants.add(raw.substring(1));
  } else if (raw.length == 14) {
    final gtin13 = raw.substring(1);
    variants.add(_renormalizeEan13(gtin13));
    if (gtin13.startsWith('0')) variants.add(gtin13.substring(1));
  }

  return variants.toList();
}

String _renormalizeEan13(String ean) {
  final fixed = '${ean.substring(0, 12)}${_ean13CheckDigit(ean.substring(0, 12))}';
  return fixed == ean ? ean : fixed;
}

int _ean13CheckDigit(String first12) {
  var sum = 0;
  for (var i = 0; i < first12.length; i++) {
    final digit = first12.codeUnitAt(i) - 0x30;
    sum += i.isEven ? digit : digit * 3;
  }
  final mod = sum % 10;
  return mod == 0 ? 0 : 10 - mod;
}