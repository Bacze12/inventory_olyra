import 'package:flutter/widgets.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/settings_repository.dart';

/// Guarda el idioma elegido por el usuario en la tabla settings y expone el
/// [Locale] activo para que `MaterialApp` pueda reaccionar al cambio.
class LanguageProvider extends ChangeNotifier {
  LanguageProvider(this._repository);

  final SettingsRepository _repository;

  Locale _locale = Locale(AppConstants.defaultLanguage);
  Locale get locale => _locale;

  String get languageCode => _locale.languageCode;

  Future<void> init() async {
    try {
      final saved = await _repository.getOr(
        AppConstants.settingLanguage,
        AppConstants.defaultLanguage,
      );
      _locale = Locale(saved);
    } catch (_) {
      _locale = Locale(AppConstants.defaultLanguage);
    }
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (code == _locale.languageCode) return;
    _locale = Locale(code);
    notifyListeners();
    try {
      await _repository.set(AppConstants.settingLanguage, code);
    } catch (_) {}
  }
}