import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dashboard/dashboard_block.dart' show BellSound;
import 'blocks/bell_player.dart';

/// Un chronomètre : démarrer/arrêter (même bouton) et remettre à zéro.
///
/// S'appuie sur [Stopwatch] (horloge monotone) : ni changement d'heure ni
/// veille de l'appli ne le font dériver, et il continue de courir pendant
/// qu'aucune carte ne le dessine.
///
/// Notifie aux **changements d'état** seulement (démarré, arrêté, remis à
/// zéro) — jamais à chaque tic. Le défilement des secondes est l'affaire du
/// widget qui l'affiche, qui ne tourne que tant qu'il est à l'écran.
class StopwatchController extends ChangeNotifier {
  final Stopwatch _watch = Stopwatch();

  Duration get elapsed => _watch.elapsed;
  bool get isRunning => _watch.isRunning;

  /// Ni démarré ni cumulé : le bouton « remettre à zéro » n'a rien à faire.
  bool get isZero => !_watch.isRunning && _watch.elapsedMicroseconds == 0;

  void toggle() {
    if (_watch.isRunning) {
      _watch.stop();
    } else {
      _watch.start();
    }
    notifyListeners();
  }

  /// Remet à zéro **et arrête** : on repart d'un chrono vierge, pas d'un
  /// chrono qui continue de tourner sous les doigts.
  void reset() {
    _watch
      ..stop()
      ..reset();
    notifyListeners();
  }
}

/// Un minuteur : compte à rebours depuis [durationS], démarrer/arrêter (même
/// bouton) et remise à zéro.
///
/// **Détecte lui-même son échéance** (un `Timer` d'une seule fois, armé au
/// démarrage) plutôt que de laisser un widget la constater : la page qui le
/// montre peut ne pas être à l'écran quand il se termine, et c'est
/// précisément là que le son compte. Le son est joué par un [BellPlayer] que
/// le minuteur possède (flux d'alarme, traverse le mode silencieux).
///
/// Fini, il le reste jusqu'à un appui : le fond clignote tant qu'on n'a pas
/// acquitté, et l'appui sur le bouton principal remet à zéro.
class TimerController extends ChangeNotifier {
  final Stopwatch _watch = Stopwatch();
  final BellPlayer _bell = BellPlayer();
  Timer? _due;
  bool _finished = false;
  int _durationS = 60;
  BellSound? _sound;

  /// Réglages du bloc, relus à chaque construction. Un minuteur en cours ou
  /// fini garde sa durée : la changer sous les doigts décalerait l'échéance.
  void configure(int durationS, BellSound? sound) {
    _sound = sound;
    if (!_watch.isRunning && !_finished && _watch.elapsedMicroseconds == 0) {
      _durationS = durationS;
    }
  }

  bool get isRunning => _watch.isRunning;
  bool get isFinished => _finished;
  bool get isUntouched => !_finished && _watch.elapsedMicroseconds == 0;

  Duration get remaining {
    if (_finished) return Duration.zero;
    final left = Duration(seconds: _durationS) - _watch.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  void toggle() {
    if (_finished) {
      reset();
      return;
    }
    if (_watch.isRunning) {
      _watch.stop();
      _due?.cancel();
    } else {
      _watch.start();
      _due = Timer(remaining, _finish);
    }
    notifyListeners();
  }

  void reset() {
    _due?.cancel();
    _watch
      ..stop()
      ..reset();
    _finished = false;
    unawaited(_bell.stop());
    notifyListeners();
  }

  void _finish() {
    _watch.stop();
    _finished = true;
    final sound = _sound;
    if (sound != null) unawaited(_bell.start(sound));
    notifyListeners();
  }

  @override
  void dispose() {
    _due?.cancel();
    _bell.dispose();
    super.dispose();
  }
}

/// Les chronomètres de la sortie, par identité (`StopwatchBlock.id`).
///
/// Vit dans la coquille et non dans le widget : le `PageView` reconstruit les
/// pages qu'on quitte, et un chrono qui repartirait de zéro en changeant de
/// page serait inutilisable. Deux composants de même `id` (une page de
/// défilement et une page rangée derrière le menu, par exemple) se partagent
/// donc le même chrono.
class StopwatchRegistry {
  final Map<String, StopwatchController> _byId = {};
  final Map<String, TimerController> _timersById = {};

  StopwatchController of(String id) =>
      _byId.putIfAbsent(id, StopwatchController.new);

  /// Les minuteurs ont leur propre espace d'identités : un chrono et un
  /// minuteur de même `id` ne se confondent pas.
  TimerController timerOf(String id) =>
      _timersById.putIfAbsent(id, TimerController.new);

  void dispose() {
    for (final controller in _byId.values) {
      controller.dispose();
    }
    _byId.clear();
    for (final timer in _timersById.values) {
      timer.dispose();
    }
    _timersById.clear();
  }
}
