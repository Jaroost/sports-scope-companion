import 'package:flutter_blue_plus/flutter_blue_plus.dart' show Guid;

import '../sensor_profile.dart';

/// Ce que le relais sait rediffuser : les trois services qu'une montre ou un
/// compteur sait lire. Le Di2, le radar et la batterie n'y sont pas — aucun
/// récepteur de poignet n'en fait rien, et les rediffuser ferait de l'appli un
/// faux Shimano.
const relayableKinds = [
  SensorKind.heartRate,
  SensorKind.power,
  SensorKind.speedCadence,
];

/// La capacité que porte cette caractéristique, si le relais sait la rediffuser.
SensorKind? relayKindOf(String characteristicUuid) {
  for (final profile in sensorProfiles) {
    if (!relayableKinds.contains(profile.kind)) continue;
    if (profile.characteristic == Guid(characteristicUuid)) return profile.kind;
  }
  return null;
}

/// Qui a la parole, caractéristique par caractéristique, dans le flux rediffusé.
///
/// Une caractéristique de mesure est un **flux cumulatif** (tours de manivelle,
/// tours de roue) : tricoter deux capteurs dedans donne au récepteur des deltas
/// absurdes. La première source vue garde donc la main, et ne la perd qu'après
/// [silence] sans trame — alors une autre prend la suite. Pur : l'horodatage
/// vient de la trame.
class RelayGate {
  RelayGate({this.silence = const Duration(seconds: 5)});

  final Duration silence;

  final _owner = <SensorKind, ({String source, DateTime at})>{};

  bool accept(SensorKind kind, String? source, DateTime at) {
    final src = source ?? '';
    final current = _owner[kind];
    if (current == null ||
        current.source == src ||
        at.difference(current.at) > silence) {
      _owner[kind] = (source: src, at: at);
      return true;
    }
    return false;
  }

  void reset() => _owner.clear();
}
