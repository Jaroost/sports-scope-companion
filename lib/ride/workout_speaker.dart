import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lit à voix haute la description d'un bloc d'entraînement à son début.
///
/// Même contexte audio que `WorkoutCuePlayer` : le guidage de navigation,
/// qui sort au volume multimédia et fait baisser la musique le temps de la
/// phrase au lieu de la couper — un HIIT parle à chaque intervalle, un focus
/// exclusif serait insupportable.
///
/// Jamais d'exception vers l'appelant : une voix absente (aucun moteur de
/// synthèse installé) vaut « pas de voix », la sortie continue avec ses bips.
class WorkoutSpeaker {
  final _tts = FlutterTts();
  bool _ready = false;

  Future<void> warmUp() async {
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setAudioAttributesForNavigation();
      _ready = true;
    } catch (e) {
      debugPrint('[entraînement] synthèse vocale indisponible : $e');
    }
  }

  /// Un texte vide ne dit rien. Une phrase encore en cours est coupée : au
  /// changement de bloc, c'est la consigne du nouveau qui compte.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    // Préparée à la demande : un tap sur la pastille doit parler même quand
    // le profil coupe les sons et que [warmUp] n'a jamais été appelée.
    if (!_ready) await warmUp();
    if (!_ready) return;
    try {
      await _tts.stop();
      // `focus: true` : sans lui flutter_tts ne demande aucun focus audio et la
      // musique continue à plein volume sous la voix. Il demande un focus
      // transitoire « baisse le volume des autres » et le rend à la fin de la
      // phrase (ou à son interruption).
      await _tts.speak(text, focus: true);
    } catch (e) {
      debugPrint('[entraînement] lecture vocale perdue : $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
