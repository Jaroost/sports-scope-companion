import 'trainer_power_model.dart';

/// Mode apprentissage de la calibration « frein et cadence » : le cycliste
/// pédale à des cadences différentes, l'appli repère seule les **paliers**
/// (cadence tenue, puissance posée) et en tire un relevé lissé par palier.
///
/// **Un palier, pas un échantillon.** La puissance d'un vélo d'appartement
/// bouge à chaque coup de pédale ; un relevé par seconde donnerait à
/// `TrainerPowerModel` un nuage bruité. La **médiane** d'un palier tenu
/// ([plateauSamples] s dans [cadenceTolerance]) est le premier lissage, la loi
/// de puissance ajustée sur plusieurs paliers le second.
///
/// **Elle s'arrête d'elle-même** : [isComplete] dès que [neededPlateaus]
/// paliers couvrent au moins [neededSpan] tr/min à ce niveau. Plus de paliers
/// n'apprendraient rien à l'exposant, et chaque minute de plus au rouleau est
/// une minute que le cycliste n'a pas à passer à pédaler pour l'appli.
///
/// Un palier se mesure **à un niveau de frein donné** : changer de niveau en
/// cours de route repart de zéro, sinon on mélangerait deux courbes. Le
/// décompte (et l'arrêt) est donc par niveau.
///
/// Pur et sans horloge : on l'alimente à raison d'un [feed] par seconde.
class TrainerLearningSession {
  TrainerLearningSession({
    this.plateauSamples = 8,
    this.cadenceTolerance = 6,
    this.minCadence = 30,
    this.minGap = 10,
    this.neededPlateaus = 4,
    this.neededSpan = 30,
  });

  final int plateauSamples;

  /// Écart maximal (tr/min) entre la plus basse et la plus haute cadence d'un
  /// palier.
  final double cadenceTolerance;

  /// Sous cette cadence on ne pédale pas vraiment : un pied qui traîne n'est
  /// pas un palier.
  final double minCadence;

  /// Deux paliers à moins de [minGap] tr/min l'un de l'autre sont le même.
  final double minGap;

  final int neededPlateaus;
  final double neededSpan;

  /// Cadences cibles que l'on propose, dans l'ordre où elles couvrent le mieux
  /// la plage utile d'un cycliste.
  static const targetCadences = <double>[60, 90, 75, 105, 120];

  final _window = <_Sample>[];
  final _plateaus = <TrainerCalibrationPoint>[];
  int? _level;

  /// Les paliers retenus, tous niveaux confondus, dans l'ordre de détection.
  List<TrainerCalibrationPoint> get plateaus => List.unmodifiable(_plateaus);

  /// Les paliers du niveau en cours.
  List<TrainerCalibrationPoint> get currentPlateaus => [
    for (final p in _plateaus)
      if (p.resistance == _level) p,
  ];

  /// Combien d'échantillons stables d'affilée (pour une jauge de progression).
  int get stableSamples => _window.length;

  bool get isComplete {
    final here = currentPlateaus;
    if (here.length < neededPlateaus) return false;
    final cadences = [for (final p in here) p.cadence]..sort();
    return cadences.last - cadences.first >= neededSpan;
  }

  /// La prochaine cadence à viser au niveau en cours, ou `null` quand c'est
  /// fini ou que plus aucune cible n'est libre.
  double? get nextTarget {
    if (isComplete) return null;
    final here = currentPlateaus;
    for (final target in targetCadences) {
      if (here.every((p) => (p.cadence - target).abs() >= minGap)) {
        return target;
      }
    }
    return null;
  }

  /// Un échantillon par seconde. Rend le palier tout juste validé, sinon
  /// `null`. Une mesure absente (capteur muet) vide la fenêtre : un trou n'est
  /// pas une cadence tenue.
  TrainerCalibrationPoint? feed({
    required int level,
    required double? cadence,
    required double? watts,
  }) {
    if (_level != level) {
      _level = level;
      _window.clear();
    }
    if (cadence == null ||
        watts == null ||
        cadence < minCadence ||
        watts <= 0) {
      _window.clear();
      return null;
    }
    _window.add(_Sample(cadence, watts));
    if (_window.length > plateauSamples) _window.removeAt(0);
    if (_window.length < plateauSamples) return null;

    final cadences = [for (final s in _window) s.cadence];
    final powers = [for (final s in _window) s.watts];
    if (_range(cadences) > cadenceTolerance) return null;
    final medianPower = _median(powers);
    // Une puissance qui court encore (jambes qui montent en charge) n'est pas
    // posée : on attend qu'elle se stabilise plutôt que de la figer en route.
    if (_range(powers) > medianPower * 0.3) return null;

    final plateau = TrainerCalibrationPoint(
      resistance: level,
      cadence: _median(cadences),
      watts: medianPower,
    );
    // Fenêtre vidée : le palier suivant repart de huit nouvelles secondes, et
    // un palier qu'on continue de tenir ne se recompte pas à chaque seconde.
    _window.clear();
    final known = currentPlateaus.any(
      (p) => (p.cadence - plateau.cadence).abs() < minGap,
    );
    if (known) return null;
    _plateaus.add(plateau);
    return plateau;
  }

  static double _range(List<double> values) {
    var low = values.first;
    var high = values.first;
    for (final v in values) {
      if (v < low) low = v;
      if (v > high) high = v;
    }
    return high - low;
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

class _Sample {
  const _Sample(this.cadence, this.watts);
  final double cadence;
  final double watts;
}
