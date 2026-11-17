/// Convertit les compteurs cumulés d'événements BLE (tours de manivelle ou de
/// roue) en une fréquence instantanée.
///
/// Les profils Cycling Power et CSC ne publient pas une cadence, mais un
/// couple *(tours cumulés, horodatage du dernier tour)*. La fréquence se
/// calcule par différence entre deux notifications — d'où un décodeur avec
/// état, un par capteur connecté.
///
/// Les deux compteurs bouclent : sur 16 bits pour l'horodatage (donc toutes
/// les 64 s en 1/1024 s), et sur [revolutionsBits] pour les tours. Les deltas
/// sont donc calculés modulo, sans quoi une cadence part en négatif toutes les
/// minutes.
class RevCounter {
  RevCounter({required this.timeUnitHz, this.revolutionsBits = 16});

  /// Résolution de l'horodatage : 1024 Hz partout, sauf la roue en Cycling
  /// Power qui est en 2048 Hz.
  final int timeUnitHz;

  /// Largeur du compteur de tours : 16 bits (manivelle) ou 32 (roue).
  final int revolutionsBits;

  int? _lastRevolutions;
  int? _lastEventTime;

  /// Dernière fréquence mesurée sur un vrai tour, et quand : de quoi tenir la
  /// valeur entre deux tours (voir [update]).
  double? _lastRate;
  DateTime? _lastEventAt;

  /// Bornes (secondes) du temps pendant lequel on garde la dernière fréquence
  /// sans nouveau tour. Mesuré sur un vélo d'appartement : il notifie à 1 Hz
  /// mais ne compte un tour de manivelle que toutes les 2 s à 30 tr/min, si bien
  /// qu'une trame sur deux arrive **sans nouveau tour** — lue comme « 0 », la
  /// cadence battait 0, 30, 0, 30.
  static const _minHold = 2.0;
  static const _maxHold = 4.0;

  /// Tours par seconde depuis la notification précédente.
  ///
  /// Retourne `null` sur la toute première trame (pas de référence), et 0 si
  /// aucun tour n'a eu lieu — pédalage arrêté : le capteur continue d'émettre
  /// avec un horodatage figé, ce qui doit se lire comme une cadence nulle et
  /// non comme une absence de donnée.
  ///
  /// Une trame sans nouveau tour ne dit pas « arrêté » tant qu'on n'a pas
  /// attendu plus de deux périodes du dernier tour (entre [_minHold] et
  /// [_maxHold] s) : avant, on rend `null` (pas de mesure, l'affichage garde la
  /// précédente). Au-delà seulement, 0. Un capteur qui n'a jamais tourné rend 0
  /// tout de suite. [at] est l'heure de réception ; par défaut, maintenant.
  double? update(int revolutions, int eventTime, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final prevRevs = _lastRevolutions;
    final prevTime = _lastEventTime;
    _lastRevolutions = revolutions;
    _lastEventTime = eventTime;

    if (prevRevs == null || prevTime == null) return null;

    final revsMask = (1 << revolutionsBits) - 1;
    final deltaRevs = (revolutions - prevRevs) & revsMask;
    final deltaTicks = (eventTime - prevTime) & 0xFFFF;

    if (deltaRevs == 0) {
      final rate = _lastRate;
      final lastAt = _lastEventAt;
      if (rate == null || lastAt == null || rate <= 0) return 0;
      final hold = (2 / rate).clamp(_minHold, _maxHold);
      final waited = now.difference(lastAt).inMilliseconds / 1000;
      return waited <= hold ? null : 0;
    }
    if (deltaTicks == 0) return null; // même événement republié

    final rate = deltaRevs * timeUnitHz / deltaTicks;
    _lastRate = rate;
    _lastEventAt = now;
    return rate;
  }

  void reset() {
    _lastRevolutions = null;
    _lastEventTime = null;
    _lastRate = null;
    _lastEventAt = null;
  }
}
