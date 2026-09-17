import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';

/// Error controlado cuando la nube no está configurada (sin credenciales).
class SupabaseNotConfiguredException implements Exception {
  @override
  String toString() =>
      'Supabase no está configurado: faltan SUPABASE_URL / SUPABASE_ANON_KEY.';
}

/// Error controlado cuando no hay sesión de usuario autenticada (necesaria
/// para que RLS vea `auth.uid()`).
class SupabaseSessionMissingException implements Exception {
  @override
  String toString() =>
      'No hay sesión de usuario. Inicia sesión antes de sincronizar.';
}

/// Fachada única del cliente Supabase.
///
/// La inicialización es perezosa (solo cuando se usa el primer endpoint) para
/// no ralentizar el arranque de la app en modo 100% local. Usa
/// `Supabase.initialize` del singleton (persistencia de sesión en
/// SharedPreferences) y todos los métodos validan credenciales y sesión antes
/// de tocar la red, manteniendo la política "la app nunca deja de funcionar
/// sin nube".
class SupabaseGateway {
  SupabaseGateway._();

  static final SupabaseGateway instance = SupabaseGateway._();

  SupabaseClient? _client;

  /// `true` cuando el módulo puede operar (credenciales compiladas presentes).
  bool get isConfigured => SupabaseConfig.credentialsPresent;

  Future<SupabaseClient>? _initFuture;

  /// Inicializa (una sola vez) y devuelve el cliente.
  Future<SupabaseClient> client() {
    if (!isConfigured) throw SupabaseNotConfiguredException();
    if (_client != null) return Future.value(_client!);
    return _initFuture ??= _bootstrap();
  }

  Future<SupabaseClient> _bootstrap() async {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      return _client = Supabase.instance.client;
    } finally {
      _initFuture = null;
    }
  }

  /// `true` si hay un usuario autenticado (RLS podrá filtrar con auth.uid()).
  Future<bool> hasSession() async {
    if (!isConfigured) return false;
    final client = await _safeClient();
    return client != null && client.auth.currentUser != null;
  }

  /// `auth.uid()` como String (para prefijos de Storage, etc.).
  Future<String> requireUid() async {
    final client = await _safeClient();
    if (client == null) {
      if (!isConfigured) throw SupabaseNotConfiguredException();
      // Inicialización fallida por red: se propaga para que el reintento
      // con backoff del sincronizador la maneje.
      throw SupabaseSessionMissingException();
    }
    final user = client.auth.currentUser;
    if (user == null) throw SupabaseSessionMissingException();
    return user.id;
  }

  /// Email de la sesión actual (para mostrarlo en la UI), o null.
  Future<String?> currentUserEmail() async {
    final client = await _safeClient();
    return client?.auth.currentUser?.email;
  }

  Future<void> signOut() async {
    final client = await _safeClient();
    await client?.auth.signOut();
  }

  Future<SupabaseClient?> _safeClient() async {
    if (!isConfigured) return null;
    try {
      return await client();
    } catch (_) {
      // Error transitorio (DNS/TLS/etc.): se informa como "sin sesión" para
      // no romper flujos locales; el reintento con backoff resolverá.
      return null;
    }
  }
}