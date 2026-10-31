import '../dashboard/ride_preset.dart' show ButtonGestureActions;
import '../phone/remote_keys.dart' show RemoteKey;

enum RemoteGesture { click, doubleClick, longPress }

class RemoteKeyGestureEvent {
  const RemoteKeyGestureEvent(this.key, this.gesture);

  final RemoteKey key;
  final RemoteGesture gesture;
}

/// Ce qu'une touche de télécommande Bluetooth finit par être — clic, double-clic
/// ou appui long — pure et pilotée par l'horloge qu'on lui passe, comme
/// `Di2ButtonGesturePolicy`.
///
/// Contrairement au D-Fly, qui classe lui-même le geste dans sa trame, une touche
/// HID n'est qu'un appui et un relâchement : tout se déduit des délais. D'où une
/// règle qui garde la télécommande vive : **on n'attend que ce qu'on pourrait
/// perdre**. Un clic ne patiente [doubleClickWindow] que si le double-clic de
/// cette touche a une action ; un appui ne se prolonge en appui long que si
/// celui-ci en a une, sinon il vaut un clic quelle que soit sa durée — un doigt
/// un peu lent ne doit pas rendre la touche sourde.
///
/// Le volume n'a pas de relâchement, il ne passe pas ici : voir
/// `RemoteVolumePulsePolicy`.
class RemoteKeyGesturePolicy {
  RemoteKeyGesturePolicy({
    required this.actionsOf,
    this.longPressHold = const Duration(milliseconds: 600),
    this.doubleClickWindow = const Duration(milliseconds: 300),
  });

  /// Lu à chaque décision plutôt que copié : c'est le profil qui dit si un
  /// double-clic ou un appui long existe, donc s'il y a quelque chose à attendre.
  final ButtonGestureActions Function(RemoteKey key) actionsOf;
  final Duration longPressHold;
  final Duration doubleClickWindow;

  /// Un appui sans relâchement depuis plus longtemps que ça est une trame perdue
  /// en route, pas un doigt qui insiste : le suivant repart de zéro.
  static const _staleHold = Duration(seconds: 10);

  final _held = <RemoteKey, _Held>{};
  final _waitingSecondClick = <RemoteKey, DateTime>{};

  /// Un appui ([down]) ou un relâchement, avec le geste qu'il tranche déjà —
  /// `null` quand il faut encore attendre ([resolve]).
  RemoteKeyGestureEvent? onKey(RemoteKey key, {required bool down, required DateTime at}) {
    if (down) return _onDown(key, at);
    return _onUp(key, at);
  }

  RemoteKeyGestureEvent? _onDown(RemoteKey key, DateTime at) {
    final held = _held[key];
    // Répétition du système sur une touche maintenue : même appui.
    if (held != null && at.difference(held.at) < _staleHold) return null;

    // Deuxième appui dans la fenêtre : on tranche tout de suite, sans attendre
    // son relâchement — c'est ce qui rend le double-clic aussi vif que le clic.
    final first = _waitingSecondClick.remove(key);
    if (first != null && at.difference(first) < doubleClickWindow) {
      _held[key] = _Held(at)..consumed = true;
      return RemoteKeyGestureEvent(key, RemoteGesture.doubleClick);
    }

    _held[key] = _Held(at);
    return null;
  }

  RemoteKeyGestureEvent? _onUp(RemoteKey key, DateTime at) {
    final held = _held.remove(key);
    if (held == null || held.consumed || held.longFired) return null;

    // Un appui long sans action vaut un clic : voir la doc de la classe.
    // Ici le relâchement est la dernière chance de le dire, [resolve] n'a rien
    // déclenché puisque l'appui long n'a pas d'action.
    final actions = actionsOf(key);
    if (actions.doubleClick != null) {
      _waitingSecondClick[key] = at;
      return null;
    }
    return RemoteKeyGestureEvent(key, RemoteGesture.click);
  }

  /// Les gestes que le temps seul a tranchés : un appui qui dure (appui long) et
  /// un clic dont le second n'est pas venu. À appeler sur un tic court.
  List<RemoteKeyGestureEvent> resolve(DateTime now) {
    final events = <RemoteKeyGestureEvent>[];

    for (final entry in _held.entries) {
      final held = entry.value;
      if (held.consumed || held.longFired) continue;
      if (now.difference(held.at) < longPressHold) continue;
      if (actionsOf(entry.key).longPress == null) continue;
      held.longFired = true;
      events.add(RemoteKeyGestureEvent(entry.key, RemoteGesture.longPress));
    }

    _waitingSecondClick.removeWhere((key, firstAt) {
      if (now.difference(firstAt) < doubleClickWindow) return false;
      events.add(RemoteKeyGestureEvent(key, RemoteGesture.click));
      return true;
    });

    return events;
  }
}

class _Held {
  _Held(this.at);

  final DateTime at;
  bool longFired = false;

  /// Le second appui d'un double-clic : son relâchement n'est plus un clic.
  bool consumed = false;
}
