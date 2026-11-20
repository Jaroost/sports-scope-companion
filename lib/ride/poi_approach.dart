import '../recording/gps_fix.dart';
import 'nearby_pois.dart';

/// Détecte l'arrivée près d'un POI — l'impulsion qui rallume l'écran endormi.
///
/// Pure, comme [TurnProximity] : la coquille lui donne la position et les POI
/// de la page, elle rend « un POI vient d'entrer dans le rayon ».
///
/// **Une impulsion par POI, pas un niveau.** Un café qu'on longe reste « proche »
/// pendant des dizaines de secondes : pris pour un état, il rallumerait l'écran à
/// chaque tic et le cycliste ne pourrait plus le rendormir. Chaque POI est donc
/// retenu dès qu'il a sonné, **qu'on dorme ou non** : sinon celui qu'on a dépassé
/// éveillé sonnerait au premier endormissement, au beau milieu de sa zone.
class PoiApproach {
  PoiApproach({this.radiusM = 150});

  /// Rayon d'annonce. ~15 s à 36 km/h : le temps de lever les yeux et de
  /// freiner, pas assez pour que l'écran se rallume à chaque rue.
  final double radiusM;

  final _announced = <String>{};

  /// Vrai quand au moins un POI **jamais annoncé** est dans le rayon.
  bool update({required GpsFix? fix, required List<NearbyPoi> pois}) {
    if (fix == null) return false;
    var arrived = false;
    for (final poi in pois) {
      if (GpsFix.haversineM(fix.lat, fix.lng, poi.lat, poi.lng) > radiusM) {
        continue;
      }
      if (_announced.add('${poi.type}|${poi.lat}|${poi.lng}')) arrived = true;
    }
    return arrived;
  }
}
