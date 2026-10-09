import 'dart:math' as math;

import '../training_program/training_program.dart';

/// Décide quel jalon d'un programme d'entraînement vient d'être franchi.
///
/// Même famille que `ClimbEdgePolicy`/`RideReminderPolicy` : une classe pure,
/// testable sans widget ni horloge. Contrairement aux rappels périodiques
/// (intervalles récurrents), les offsets d'un programme sont absolus et
/// strictement croissants — une simple avancée séquentielle suffit, jamais
/// plus d'un jalon franchi par tic.
///
/// Semée dès la construction sur [elapsed] déjà écoulé, et non à zéro : la
/// coquille se démonte et se remonte à chaque aller-retour à l'accueil, et
/// repartir de zéro y rejouerait aussitôt tous les jalons déjà passés — même
/// raison que `RideReminderPolicy`.
///
/// **[elapsed] n'est jamais `RideRecorder.recorded` directement** : un
/// programme peut être activé en cours de sortie, ses offsets comptent depuis
/// l'activation, pas depuis le départ. C'est `RideRecorder.workoutElapsed`
/// qui porte ce calcul (`recorded - workoutStartSeconds`) ; cette classe ne
/// fait que comparer la durée qu'on lui donne aux jalons.
class WorkoutPolicy {
  WorkoutPolicy({required this.milestones, required Duration elapsed}) {
    // `elapsed <= 0` veut dire « le programme vient d'être activé » (cf.
    // `RideRecorder.workoutElapsed`, qui repart de zéro à l'activation) : rien
    // n'a encore pu être franchi, pas même le jalon d'ouverture à offset 0. Le
    // sauter ici l'aurait fait disparaître pour toute la sortie — [read] ne
    // rappelle jamais un jalon une fois `_next` passé devant.
    if (elapsed <= Duration.zero) return;
    while (_next < milestones.length &&
        milestones[_next].offsetSeconds <= elapsed.inSeconds) {
      _next++;
    }
  }

  final List<WorkoutMilestone> milestones;
  int _next = 0;

  /// Le jalon franchi **ce tic-ci**, ou `null` — au plus un par appel, les
  /// offsets étant strictement croissants.
  WorkoutMilestone? read(Duration elapsed) {
    if (_next >= milestones.length) return null;
    if (milestones[_next].offsetSeconds > elapsed.inSeconds) return null;
    return milestones[_next++];
  }

  /// Le dernier jalon a-t-il été franchi ?
  bool get finished => _next >= milestones.length;
}

/// Décide quel son d'un programme doit se lancer maintenant.
///
/// Un son est attaché à une frontière (début ou fin d'un bloc) et à un moment
/// ([WorkoutCueTiming]) : `at` démarre sur la frontière, `before` démarre en
/// avance pour se **terminer** pile dessus — un bloc de 30 s suivi d'un son de
/// 5 s : le son part à 25 s, pas à 30.
///
/// Même famille que [WorkoutPolicy] — pure, testable sans widget ni horloge —
/// mais un état séparé : un son d'annonce précède le franchissement dont il
/// parle, les deux ne peuvent pas partager un seul curseur. Le franchissement
/// lui-même (splits/`markLap`) reste sur [WorkoutPolicy], inchangé.
///
/// Le site refuse les sons qui se chevauchent, mais l'ordre de départ de deux
/// sons (une fin `at` et un début `before` sur la même frontière) dépend de la
/// durée de chacun, connue ici seulement : on lance donc, à chaque tic, le
/// son non joué dont l'instant de départ est échu et le plus ancien.
class WorkoutCuePolicy {
  WorkoutCuePolicy({
    required this.cues,
    required this.soundDuration,
    required Duration elapsed,
  }) : _played = List.filled(cues.length, false) {
    // `elapsed <= 0` : programme tout juste activé, rien n'est joué — pas même
    // un son posé sur le départ (voir [WorkoutPolicy]).
    if (elapsed <= Duration.zero) return;
    for (var i = 0; i < cues.length; i++) {
      if (_startSeconds(cues[i]) <= elapsed.inSeconds) _played[i] = true;
    }
  }

  final List<WorkoutCue> cues;

  /// Consultée à chaque lecture plutôt que figée à la construction : les
  /// sons se préchargent en tâche de fond (`WorkoutCuePlayer.warmUp`), leur
  /// durée peut donc n'être connue qu'après coup. Une durée encore inconnue
  /// vaut zéro — l'anticipation est alors nulle, jamais un son en retard.
  final Duration Function(WorkoutSound sound) soundDuration;

  final List<bool> _played;

  /// L'instant, en secondes depuis l'activation, où [cue] doit démarrer.
  /// Rien ne précède le départ du programme : un son posé sur la frontière 0
  /// part immédiatement, quel que soit son moment.
  int _startSeconds(WorkoutCue cue) {
    if (cue.timing == WorkoutCueTiming.at || cue.boundarySeconds <= 0) {
      return cue.boundarySeconds;
    }
    final leadSeconds = (soundDuration(cue.sound).inMilliseconds / 1000).ceil();
    return math.max(0, cue.boundarySeconds - leadSeconds);
  }

  /// Le son à lancer **ce tic-ci**, ou `null` — au plus un par appel.
  WorkoutCue? read(Duration elapsed) {
    int? best;
    var bestStart = 0;
    for (var i = 0; i < cues.length; i++) {
      if (_played[i]) continue;
      final start = _startSeconds(cues[i]);
      if (start > elapsed.inSeconds) continue;
      if (best == null || start < bestStart) {
        best = i;
        bestStart = start;
      }
    }
    if (best == null) return null;
    _played[best] = true;
    return cues[best];
  }

  /// Tous les sons ont-ils été lancés ?
  bool get finished => !_played.contains(false);
}
