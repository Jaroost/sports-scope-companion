import 'dart:typed_data';

import '../samples.dart';

/// Indoor Bike Data (0x2AD2) du Fitness Machine Service (FTMS, 0x1826).
///
/// Uint16 de drapeaux, puis les champs présents **dans l'ordre des bits**,
/// chacun décalant le suivant. Piège de la spec : le bit 0 est inversé — il
/// s'appelle « More Data » et la vitesse instantanée est présente quand il
/// vaut **0**. Un bit 0 posé veut dire que la trame est un fragment sans
/// vitesse, la suite d'une trame trop longue pour un seul paquet.
///
/// On ne décode que **la vitesse et la résistance**. Le même paquet porte aussi
/// puissance, cadence et cardio, volontairement ignorés : un vélo qui expose
/// FTMS expose presque toujours aussi Cycling Power, et deux sources pour la
/// même mesure feraient écrire le hub à tour de rôle. Les champs sont tout de
/// même *sautés* à la bonne taille, sinon la résistance serait lue au mauvais
/// endroit.
class IndoorBikeDecoder {
  static const _moreData = 1 << 0;
  static const _averageSpeed = 1 << 1;
  static const _instantCadence = 1 << 2;
  static const _averageCadence = 1 << 3;
  static const _totalDistance = 1 << 4;
  static const _resistance = 1 << 5;

  List<SensorSample> decode(List<int> data, {DateTime? at}) {
    if (data.length < 2) return const [];

    final now = at ?? DateTime.now();
    final bytes = ByteData.sublistView(Uint8List.fromList(data));
    final flags = bytes.getUint16(0, Endian.little);
    var offset = 2;

    final samples = <SensorSample>[];

    if (flags & _moreData == 0) {
      if (data.length < offset + 2) return samples;
      // Unité : 0,01 km/h. Converti en m/s, l'unité du reste de l'appli.
      final raw = bytes.getUint16(offset, Endian.little);
      offset += 2;
      samples.add(SpeedSample(now, raw / 100 / 3.6));
    }

    if (flags & _averageSpeed != 0) offset += 2;
    if (flags & _instantCadence != 0) offset += 2;
    if (flags & _averageCadence != 0) offset += 2;
    if (flags & _totalDistance != 0) offset += 3;

    if (flags & _resistance != 0) {
      if (data.length < offset + 2) return samples;
      // Niveau propre à la machine, sans unité : un 12 sur un vélo ne vaut pas
      // un 12 sur un autre. Signé, comme la spec le déclare.
      samples.add(ResistanceSample(now, bytes.getInt16(offset, Endian.little)));
    }

    return samples;
  }
}
