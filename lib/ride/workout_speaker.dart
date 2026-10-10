import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../dashboard/ride_preset.dart';

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
  WorkoutSettings _settings = const WorkoutSettings();

  /// Applique le ton et la voix du profil. Appelée à chaque changement de
  /// profil : la prochaine phrase en tient compte, sans relancer le moteur.
  void configure(WorkoutSettings settings) {
    final changed = settings.voiceStyle != _settings.voiceStyle ||
        settings.voiceName != _settings.voiceName;
    _settings = settings;
    if (changed && _ready) unawaited(_applyVoice());
  }

  /// Hauteur, débit et voix. Un échec ne bloque jamais la lecture : le moteur
  /// garde alors ses valeurs par défaut.
  Future<void> _applyVoice() async {
    try {
      await _tts.setPitch(_settings.voiceStyle.pitch);
      await _tts.setSpeechRate(_settings.voiceStyle.rate);
      final voice = await _pickVoice();
      if (voice != null) await _tts.setVoice(voice);
    } catch (e) {
      debugPrint('[entraînement] réglage de la voix impossible : $e');
    }
  }

  /// La voix nommée par le profil si elle existe ; sinon la meilleure voix
  /// française : une voix « réseau » (plus expressive) avant une voix locale,
  /// hors voix signalées comme non installées.
  Future<Map<String, String>?> _pickVoice() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return null;
    final voices = <Map<String, String>>[
      for (final v in raw)
        if (v is Map && v['name'] != null && v['locale'] != null)
          {'name': '${v['name']}', 'locale': '${v['locale']}'},
    ];
    final wanted = _settings.voiceName;
    if (wanted != null) {
      for (final v in voices) {
        if (v['name'] == wanted) return v;
      }
    }
    final french = voices
        .where((v) => v['locale']!.toLowerCase().replaceAll('_', '-').startsWith('fr'))
        .toList();
    if (french.isEmpty) return null;
    french.sort((a, b) => _score(b).compareTo(_score(a)));
    return french.first;
  }

  int _score(Map<String, String> v) {
    final name = v['name']!.toLowerCase();
    var score = 0;
    if (name.contains('network')) score += 2;
    if (v['locale']!.toLowerCase().replaceAll('_', '-') == 'fr-fr') score += 1;
    return score;
  }

  Future<void> warmUp() async {
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setAudioAttributesForNavigation();
      _ready = true;
      await _applyVoice();
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

  /// Coupe la phrase en cours (sans effet s'il n'y en a pas). Appelée quand
  /// un son démarre — dont un son de fin « avant », parti en avance sur la
  /// frontière — et quand un tronçon s'ouvre sans description : la voix ne
  /// déborde ni sur un bip ni sur le tronçon suivant.
  Future<void> stop() async {
    if (!_ready) return;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
