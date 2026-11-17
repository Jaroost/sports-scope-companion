import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/trainer_learning.dart';
import 'package:sports_scope_companion/ble/trainer_power_model.dart';

TrainerCalibrationPoint? hold(
  TrainerLearningSession s, {
  required double cadence,
  required double watts,
  int level = 3,
  int seconds = 8,
}) {
  TrainerCalibrationPoint? last;
  for (var i = 0; i < seconds; i++) {
    // Un léger bruit autour de la consigne, comme un vrai coup de pédale.
    final jitter = (i.isEven ? 1 : -1) * 1.0;
    last =
        s.feed(
          level: level,
          cadence: cadence + jitter,
          watts: watts + jitter * 2,
        ) ??
        last;
  }
  return last;
}

void main() {
  test('un palier tenu donne un relevé à la médiane', () {
    final s = TrainerLearningSession();
    final p = hold(s, cadence: 60, watts: 100);
    expect(p, isNotNull);
    expect(p!.cadence, closeTo(60, 1));
    expect(p.watts, closeTo(100, 2));
    expect(p.resistance, 3);
  });

  test('une cadence qui bouge ne fait pas de palier', () {
    final s = TrainerLearningSession();
    TrainerCalibrationPoint? p;
    for (var i = 0; i < 20; i++) {
      p = s.feed(level: 3, cadence: 50 + i * 3.0, watts: 100) ?? p;
    }
    expect(p, isNull);
  });

  test('une mesure absente vide la fenêtre', () {
    final s = TrainerLearningSession();
    for (var i = 0; i < 6; i++) {
      s.feed(level: 3, cadence: 60, watts: 100);
    }
    s.feed(level: 3, cadence: null, watts: 100);
    expect(s.stableSamples, 0);
  });

  test('tenir la même cadence ne recompte pas le palier', () {
    final s = TrainerLearningSession();
    hold(s, cadence: 60, watts: 100, seconds: 40);
    expect(s.currentPlateaus.length, 1);
  });

  test('s’arrête seule avec assez de paliers répartis', () {
    final s = TrainerLearningSession();
    for (final c in [60.0, 75.0, 90.0]) {
      hold(s, cadence: c, watts: c * 1.5);
    }
    expect(s.isComplete, isFalse);
    expect(s.nextTarget, isNotNull);
    hold(s, cadence: 105, watts: 160);
    expect(s.isComplete, isTrue);
    expect(s.nextTarget, isNull);
  });

  test('quatre paliers trop serrés ne suffisent pas', () {
    final s = TrainerLearningSession(minGap: 5);
    for (final c in [60.0, 66.0, 72.0, 78.0]) {
      hold(s, cadence: c, watts: 100);
    }
    expect(s.currentPlateaus.length, 4);
    expect(s.isComplete, isFalse);
  });

  test('changer de niveau repart de zéro', () {
    final s = TrainerLearningSession();
    for (final c in [60.0, 75.0, 90.0, 105.0]) {
      hold(s, cadence: c, watts: 100, level: 3);
    }
    expect(s.isComplete, isTrue);
    s.feed(level: 4, cadence: 60, watts: 100);
    expect(s.isComplete, isFalse);
    expect(s.plateaus.length, 4);
  });
}
