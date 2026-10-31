import 'package:flutter/services.dart';

import '../dashboard/ride_preset.dart';

/// Pilote le lecteur de musique d'Android (volume, piste, lecture/pause) pour
/// les commandes `media_*` du profil — voir `MediaControl.kt` côté natif.
class MediaControl {
  MediaControl._();

  static const _channel = MethodChannel('sports_scope/media');

  /// Sans état et sans échec bruyant : une commande ratée (plateforme sans
  /// canal, aucun lecteur actif) ne doit jamais casser la sortie.
  static Future<void> run(MediaCommand command) async {
    try {
      await _channel.invokeMethod<void>('command', command.token);
    } on PlatformException {
      // Rien à lire / à régler : sans effet.
    } on MissingPluginException {
      // Hors Android (tests, simulateur) : sans effet.
    }
  }
}
