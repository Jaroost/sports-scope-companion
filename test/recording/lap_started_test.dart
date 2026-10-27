import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';

void main() {
  test('un tour lancé par bouton (sans étiquette) se reconnaît par sa série', () {
    const lap = LapStarted(series: 'sprint', label: null, index: 0);
    expect(lap.isNamed('sprint'), isTrue);
    expect(lap.isNamed('autre'), isFalse);
  });

  test("l'étiquette reste reconnue", () {
    const lap = LapStarted(series: 'default', label: 'Relance', index: 2);
    expect(lap.isNamed('Relance'), isTrue);
  });
}
