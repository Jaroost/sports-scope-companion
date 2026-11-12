import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Allume / éteint la lampe torche du téléphone (commande `toggle_torch` du
/// profil) — voir `TorchControl.kt` côté natif.
class TorchControl {
  TorchControl._();

  static const _channel = MethodChannel('sports_scope/torch');

  /// État connu, pour que le bouton montre s'il est allumé.
  static final ValueNotifier<bool> isOn = ValueNotifier(false);

  /// Bascule la torche. Sans échec bruyant : pas de flash, caméra occupée ou
  /// plateforme sans canal ne doivent jamais casser la sortie.
  static Future<void> toggle() async {
    try {
      isOn.value = await _channel.invokeMethod<bool>('toggle') ?? false;
    } on PlatformException {
      // Sans effet.
    } on MissingPluginException {
      // Hors Android (tests, simulateur) : sans effet.
    }
  }
}
