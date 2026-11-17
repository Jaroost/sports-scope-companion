import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/decoders/indoor_bike.dart';
import 'package:sports_scope_companion/ble/samples.dart';
import 'package:sports_scope_companion/ble/trainer_power_model.dart';

void main() {
  cadenceOnly();
  // flags : cadence (bit 2) + résistance (bit 5) + puissance (bit 6).
  // vitesse 25,00 km/h, cadence 90 tr/min (180 × 0,5), résistance 12, 150 W.
  final frame = [0x64, 0x00, 0xC4, 0x09, 0xB4, 0x00, 0x0C, 0x00, 0x96, 0x00];

  test('ignore watts et cadence par défaut, mais lit la résistance', () {
    final samples = IndoorBikeDecoder().decode(frame);
    expect(samples.whereType<PowerSample>(), isEmpty);
    expect(samples.whereType<CadenceSample>(), isEmpty);
    expect(samples.whereType<ResistanceSample>().single.level, 12);
  });

  test('lit watts et cadence sur demande', () {
    final samples = IndoorBikeDecoder(includePower: true, includeCadence: true)
        .decode(frame);
    expect(samples.whereType<PowerSample>().single.watts, 150);
    expect(samples.whereType<CadenceSample>().single.rpm, 90);
    expect(samples.whereType<SpeedSample>().single.metersPerSecond,
        closeTo(25 / 3.6, 1e-6));
  });
}

void cadenceOnly() {
  // Sans FTMS, tous les relevés sont au niveau 0 : la courbe ne dépend que de
  // la cadence.
  test('un vélo sans résistance se corrige par la cadence seule', () {
    final model = TrainerPowerModel(const [
      TrainerCalibrationPoint(resistance: 0, cadence: 60, watts: 100),
      TrainerCalibrationPoint(resistance: 0, cadence: 90, watts: 225),
    ]);
    expect(model.estimate(resistance: 0, cadence: 60), closeTo(100, 0.5));
    expect(model.estimate(resistance: 0, cadence: 90), closeTo(225, 0.5));
    expect(model.estimate(resistance: 0, cadence: 0), 0);
  });
}
