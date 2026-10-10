import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../training_program/training_program.dart';

/// Joue les sons des jalons d'un programme d'entraînement — même patron que
/// `ClimbAlertPlayer` : un lecteur par son, préchargé au montage, pour ne pas
/// ouvrir de fichier au moment du front.
///
/// Même contexte audio que `ClimbAlertPlayer` (guidage de navigation, baisse
/// la musique le temps du bip), **pas** le flux alarme à focus exclusif de
/// `BellPlayer` : un HIIT peut sonner toutes les 30 secondes, un flux qui
/// coupe la musique à chaque fois serait bien plus intrusif qu'un col ou
/// qu'une voiture qui approche, deux événements rares par comparaison.
class WorkoutCuePlayer {
  final _players = <WorkoutSound, AudioPlayer>{};

  /// Durée de chaque son, connue une fois [warmUp] terminé — c'est elle qui
  /// permet à `WorkoutCuePolicy` de faire démarrer le son assez tôt pour
  /// qu'il se termine au départ du jalon plutôt que d'y commencer.
  final _durations = <WorkoutSound, Duration>{};

  /// `Duration.zero` tant que [warmUp] n'a pas résolu ce son (ou a échoué) :
  /// une durée inconnue vaut « pas d'anticipation », jamais un son qui parte
  /// en retard sur son jalon.
  Duration durationOf(WorkoutSound sound) => _durations[sound] ?? Duration.zero;

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceNavigationGuidance,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  Future<void> warmUp() async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
      for (final sound in WorkoutSound.values) {
        final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        // Le contexte posé sur **ce** lecteur, en plus du global : le global
        // est partagé avec le radar, les cols et la batterie, et ne vaut que
        // pour les lecteurs créés après lui. Ce son est celui qui doit
        // baisser la musique, pas dépendre de qui a chargé le dernier.
        await player.setAudioContext(_context);
        await player.setSource(AssetSource(sound.asset));
        _players[sound] = player;
        final duration = await player.getDuration();
        if (duration != null) _durations[sound] = duration;
      }
    } catch (e) {
      debugPrint('[entraînement] sons indisponibles : $e');
    }
  }

  /// Jusqu'à quand un son lancé par [play] est censé sonner. Posé à
  /// l'appel même : `seek` + `resume` sont asynchrones, l'état du lecteur
  /// ne dit « en lecture » qu'un instant plus tard, et la voix ne doit pas
  /// s'y glisser entre-temps.
  DateTime? _busyUntil;

  /// Un son est-il en cours (ou sur le point de l'être) ? C'est ce que la voix
  /// attend pour ne pas se superposer à un bip (`WorkoutSpeaker`).
  bool get busy {
    final until = _busyUntil;
    if (until != null && DateTime.now().isBefore(until)) return true;
    return _players.values.any((p) => p.state == PlayerState.playing);
  }

  void play(WorkoutSound sound) {
    final player = _players[sound];
    if (player == null) return;
    _busyUntil = DateTime.now().add(durationOf(sound) + const Duration(milliseconds: 300));
    player.seek(Duration.zero).then((_) => player.resume()).catchError((
      Object e,
    ) {
      debugPrint('[entraînement] bip perdu : $e');
    });
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
