import 'dart:math' as math;

/// Un relevé de calibration : à ce niveau de résistance et cette cadence, la
/// puissance réelle valait [watts] (donnée par le cycliste, d'une autre source).
class TrainerCalibrationPoint {
  const TrainerCalibrationPoint({
    required this.resistance,
    required this.cadence,
    required this.watts,
  });

  final int resistance;
  final double cadence;
  final double watts;

  Map<String, Object> toJson() =>
      {'resistance': resistance, 'cadence': cadence, 'watts': watts};

  /// Ne lève jamais : un point illisible est ignoré, pas fatal au démarrage.
  static TrainerCalibrationPoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final resistance = raw['resistance'];
    final cadence = raw['cadence'];
    final watts = raw['watts'];
    if (resistance is! num || cadence is! num || watts is! num) return null;
    if (cadence <= 0 || watts <= 0) return null;
    return TrainerCalibrationPoint(
      resistance: resistance.round(),
      cadence: cadence.toDouble(),
      watts: watts.toDouble(),
    );
  }
}

/// Estime la puissance d'un vélo d'appartement imprécis à partir de ce qu'il
/// mesure bien — son niveau de résistance et la cadence — et de quelques
/// relevés pris par le cycliste contre une référence.
///
/// **Par niveau de résistance, une loi de puissance `P = a · cadence^b`.** Un
/// frein à friction ou magnétique oppose un couple à peu près fixé par le
/// niveau, donc la puissance suit la cadence ; l'exposant dit à quel point
/// (1 pour un couple constant, plus pour un frein qui durcit avec la vitesse).
/// Avec **deux relevés ou plus** à un niveau, l'exposant est ajusté (moindres
/// carrés en log-log, borné à [_minExponent, _maxExponent] pour qu'un relevé
/// bruité ne produise pas une courbe absurde). Avec **un seul**, on suppose
/// [defaultExponent] : c'est une hypothèse, pas une mesure, et un second relevé
/// à une autre cadence la remplace.
///
/// **Entre deux niveaux calibrés, interpolation linéaire** des puissances que
/// donnent les deux courbes à cette cadence. **Hors de la plage calibrée, on
/// reste sur le niveau le plus proche** plutôt que d'extrapoler : un niveau
/// jamais relevé ne doit pas inventer des watts de plus en plus fantaisistes.
/// L'écran de calibration annonce la plage couverte.
///
/// Pur et sans horloge.
class TrainerPowerModel {
  TrainerPowerModel(
    Iterable<TrainerCalibrationPoint> points, {
    this.defaultExponent = 1.0,
  }) {
    final byLevel = <int, List<TrainerCalibrationPoint>>{};
    for (final point in points) {
      if (point.cadence <= 0 || point.watts <= 0) continue;
      byLevel.putIfAbsent(point.resistance, () => []).add(point);
    }
    for (final level in byLevel.keys.toList()..sort()) {
      _levels.add(level);
      _curves.add(_Curve.fit(byLevel[level]!, defaultExponent));
    }
  }

  static const _minExponent = 0.5;
  static const _maxExponent = 3.0;

  final double defaultExponent;
  final _levels = <int>[];
  final _curves = <_Curve>[];

  bool get isEmpty => _levels.isEmpty;

  /// Les niveaux de résistance relevés, du plus bas au plus haut.
  List<int> get calibratedLevels => List.unmodifiable(_levels);

  /// La puissance estimée en watts, ou `null` si rien n'a été relevé.
  /// Une cadence nulle vaut zéro watt : on ne produit rien sans pédaler.
  double? estimate({required int resistance, required double cadence}) {
    if (_levels.isEmpty) return null;
    if (cadence <= 0) return 0;

    if (resistance <= _levels.first) return _curves.first.at(cadence);
    if (resistance >= _levels.last) return _curves.last.at(cadence);

    var upper = 1;
    while (_levels[upper] < resistance) {
      upper++;
    }
    final lower = upper - 1;
    final t = (resistance - _levels[lower]) / (_levels[upper] - _levels[lower]);
    final low = _curves[lower].at(cadence);
    final high = _curves[upper].at(cadence);
    return low + (high - low) * t;
  }

  static double clampExponent(double b) =>
      b.clamp(_minExponent, _maxExponent).toDouble();
}

/// `P = a · c^b`, ajustée sur les relevés d'un niveau.
class _Curve {
  const _Curve(this.a, this.b);

  final double a;
  final double b;

  double at(double cadence) => a * math.pow(cadence, b);

  factory _Curve.fit(List<TrainerCalibrationPoint> points, double fallback) {
    final xs = [for (final p in points) math.log(p.cadence)];
    final ys = [for (final p in points) math.log(p.watts)];
    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;

    var covariance = 0.0;
    var variance = 0.0;
    for (var i = 0; i < xs.length; i++) {
      covariance += (xs[i] - meanX) * (ys[i] - meanY);
      variance += (xs[i] - meanX) * (xs[i] - meanX);
    }

    // Variance nulle : tous les relevés à la même cadence (ou un seul), la
    // pente est indéterminée — on retombe sur l'hypothèse, pas sur un NaN.
    final b = variance > 1e-9
        ? TrainerPowerModel.clampExponent(covariance / variance)
        : fallback;
    return _Curve(math.exp(meanY - b * meanX), b);
  }
}
