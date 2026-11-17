import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/decoders/rev_counter.dart';

void main() {
  final t0 = DateTime(2026, 11, 17, 12);
  DateTime at(double s) => t0.add(Duration(milliseconds: (s * 1000).round()));

  // Mesure du situs fitness : notifications à 1 Hz, un tour toutes les 2 s
  // (2048 ticks à 1024 Hz) = 30 tr/min.
  test('une trame sans nouveau tour ne ramène pas la cadence à 0', () {
    final c = RevCounter(timeUnitHz: 1024);
    expect(c.update(86, 0, at: at(0)), isNull); // référence
    expect(c.update(87, 2048, at: at(2)), closeTo(0.5, 1e-9)); // 30 tr/min
    // Trame suivante, 1 s plus tard, sans nouveau tour : on garde, pas 0.
    expect(c.update(87, 2048, at: at(3)), isNull);
    expect(c.update(88, 4096, at: at(4)), closeTo(0.5, 1e-9));
  });

  test('sans tour pendant plus de deux périodes, la cadence tombe à 0', () {
    final c = RevCounter(timeUnitHz: 1024);
    c.update(86, 0, at: at(0));
    c.update(87, 2048, at: at(2));
    expect(c.update(87, 2048, at: at(5)), isNull); // 3 s : on tient encore
    expect(c.update(87, 2048, at: at(6.5)), 0); // > 4 s : arrêté
  });

  test('un capteur qui n\'a jamais tourné rend 0 tout de suite', () {
    final c = RevCounter(timeUnitHz: 1024);
    c.update(86, 2772, at: at(0));
    expect(c.update(86, 2772, at: at(1)), 0);
  });

  test('reset oublie la dernière fréquence', () {
    final c = RevCounter(timeUnitHz: 1024);
    c.update(86, 0, at: at(0));
    c.update(87, 2048, at: at(2));
    c.reset();
    c.update(90, 100, at: at(10));
    expect(c.update(90, 100, at: at(11)), 0);
  });
}
