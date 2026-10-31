import '../dashboard/ride_preset.dart' show ButtonGestureActions;
import '../phone/remote_keys.dart' show RemoteKey;
import 'remote_key_gesture_policy.dart';

/// Le pendant de [RemoteKeyGesturePolicy] pour les touches de volume, qui ne
/// livrent qu'une impulsion par pression — jamais de relâchement. Tout se
/// déduit donc du rythme des impulsions :
///
/// - **double-clic** : deux impulsions à moins de [doubleClickWindow] ;
/// - **appui long** : la répétition du système sur une touche maintenue, soit des
///   impulsions à moins de [repeatGap] les unes des autres — plus vif que ce
///   qu'un doigt sait taper. Un seul appui long par maintien, quel que soit le
///   nombre de répétitions.
///
/// Même règle que la politique sœur : **on n'attend que ce qu'on pourrait
/// perdre**. Une impulsion est un clic tout de suite si ni le double-clic ni
/// l'appui long de cette touche n'a d'action ; sinon elle patiente juste assez
/// pour savoir si une suivante la rend double ou longue.
///
/// Le compromis assumé : avec un appui long assigné, deux impulsions plus
/// rapprochées que [repeatGap] se lisent comme un maintien, pas comme un
/// double-clic.
class RemoteVolumePulsePolicy {
  RemoteVolumePulsePolicy({
    required this.actionsOf,
    this.repeatGap = const Duration(milliseconds: 150),
    this.doubleClickWindow = const Duration(milliseconds: 300),
  });

  /// Lu à chaque décision, comme [RemoteKeyGesturePolicy.actionsOf].
  final ButtonGestureActions Function(RemoteKey key) actionsOf;
  final Duration repeatGap;
  final Duration doubleClickWindow;

  final _lastPulse = <RemoteKey, DateTime>{};
  final _pendingClick = <RemoteKey, DateTime>{};
  final _longFired = <RemoteKey>{};

  /// Une impulsion, avec le geste qu'elle tranche déjà — `null` quand il faut
  /// encore attendre ([resolve]).
  RemoteKeyGestureEvent? onPulse(RemoteKey key, {required DateTime at}) {
    final actions = actionsOf(key);
    final last = _lastPulse[key];
    _lastPulse[key] = at;

    final repeating = last != null && at.difference(last) < repeatGap;
    if (actions.longPress != null && repeating) {
      // La première impulsion du maintien attendait en clic : c'était le début
      // de l'appui, pas un clic.
      _pendingClick.remove(key);
      if (!_longFired.add(key)) return null;
      return RemoteKeyGestureEvent(key, RemoteGesture.longPress);
    }
    if (!repeating) _longFired.remove(key);

    final first = _pendingClick[key];
    if (first != null &&
        actions.doubleClick != null &&
        at.difference(first) < doubleClickWindow) {
      _pendingClick.remove(key);
      return RemoteKeyGestureEvent(key, RemoteGesture.doubleClick);
    }

    if (actions.doubleClick == null && actions.longPress == null) {
      return RemoteKeyGestureEvent(key, RemoteGesture.click);
    }
    _pendingClick[key] = at;
    return null;
  }

  /// Les clics dont la suite n'est pas venue. À appeler sur un tic court.
  List<RemoteKeyGestureEvent> resolve(DateTime now) {
    final events = <RemoteKeyGestureEvent>[];
    _pendingClick.removeWhere((key, firstAt) {
      final wait =
          actionsOf(key).doubleClick != null ? doubleClickWindow : repeatGap;
      if (now.difference(firstAt) < wait) return false;
      events.add(RemoteKeyGestureEvent(key, RemoteGesture.click));
      return true;
    });
    return events;
  }
}
