import 'package:flutter/foundation.dart';

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

/// Les chronomètres de la sortie, par identité (`StopwatchBlock.id`).
///
/// Vit dans la coquille et non dans le widget : le `PageView` reconstruit les
/// pages qu'on quitte, et un chrono qui repartirait de zéro en changeant de
/// page serait inutilisable. Deux composants de même `id` (une page de
/// défilement et une page rangée derrière le menu, par exemple) se partagent
/// donc le même chrono.
class StopwatchRegistry {
  final Map<String, StopwatchController> _byId = {};

  StopwatchController of(String id) =>
      _byId.putIfAbsent(id, StopwatchController.new);

  void dispose() {
    for (final controller in _byId.values) {
      controller.dispose();
    }
    _byId.clear();
  }
}
