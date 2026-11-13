import 'dart:async';

import 'gps_fix.dart';
import 'gps_source.dart';

/// La position simulée par la page de débug du site (`/routes/:token/simulate`).
///
/// Le faux GPS vit **dans la page** : c'est elle qui rejoue le tracé et remplace
/// `navigator.geolocation`, ce qui suffit à la carte. Mais Flutter lit, lui, le
/// vrai récepteur pour le tableau de bord, l'enregistreur et le trajet parcouru ;
/// laissés seuls, ils montreraient la vraie position à côté d'une carte qui
/// roule. La page renvoie donc chaque fix émis (message `sim_fix`), et ce
/// singleton — même patron que `DebugLog.instance` — les met à disposition.
///
/// Un singleton et non un objet passé de main à la coquille : le message arrive
/// dans `RideShellPage`, l'enregistreur est construit dans `main.dart`, et rien
/// ne relie les deux sinon l'application elle-même.
class SimulatedGps {
  SimulatedGps._();

  static final instance = SimulatedGps._();

  final _controller = StreamController<GpsFix>.broadcast();

  GpsFix? _latest;
  bool _engaged = false;

  /// Vrai dès qu'un fix simulé a été reçu, et **jusqu'à [reset]** : une perte de
  /// signal simulée (case décochée dans la page) fait taire le flux, elle ne
  /// doit pas rendre la main au vrai GPS — ce serait téléporter le cycliste.
  bool get engaged => _engaged;

  /// Le dernier fix simulé, ou `null` hors simulation.
  GpsFix? get latest => _engaged ? _latest : null;

  Stream<GpsFix> get fixes => _controller.stream;

  /// À appeler à l'ouverture d'une navigation ordinaire : la simulation d'une
  /// sortie précédente ne doit pas survivre à la suivante.
  void reset() {
    _engaged = false;
    _latest = null;
  }

  /// Un message `sim_fix` de la page. Ignore ce qui est illisible : un faux GPS
  /// de débug ne doit jamais faire tomber la navigation.
  void push(Map<dynamic, dynamic> message) {
    final lat = (message['lat'] as num?)?.toDouble();
    final lng = (message['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final at = (message['at'] as num?)?.toInt();
    final speed = (message['speedMps'] as num?)?.toDouble();
    final fix = GpsFix(
      at: at == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(at),
      lat: lat,
      lng: lng,
      altitudeM: (message['altitudeM'] as num?)?.toDouble(),
      speedMps: speed != null && speed >= 0 ? speed : null,
      headingDeg: (message['headingDeg'] as num?)?.toDouble(),
      accuracyM: (message['accuracyM'] as num?)?.toDouble(),
      // Marqué comme mocké : `RideRecorder.handleFix` écarte alors tout point
      // réel qui arriverait encore du récepteur pendant la simulation.
      isMocked: true,
    );
    _engaged = true;
    _latest = fix;
    _controller.add(fix);
  }
}

/// La source de l'enregistreur : le vrai GPS, sauf quand la page simule.
///
/// Le vrai récepteur reste abonné (un abonnement par sortie, comme avant) mais
/// ses points sont jetés dès que la simulation a pris la main.
class SwitchableGpsSource implements GpsSource {
  const SwitchableGpsSource({this.real = const GeolocatorGpsSource()});

  final GpsSource real;

  @override
  Future<void> ensureReady() => real.ensureReady();

  @override
  Stream<GpsFix> watch() {
    final simulated = SimulatedGps.instance;
    late final StreamController<GpsFix> controller;
    StreamSubscription<GpsFix>? realSub;
    StreamSubscription<GpsFix>? simSub;

    controller = StreamController<GpsFix>(
      onListen: () {
        realSub = real.watch().listen(
          (fix) {
            if (!simulated.engaged) controller.add(fix);
          },
          onError: controller.addError,
        );
        simSub = simulated.fixes.listen(controller.add);
      },
      onCancel: () async {
        await realSub?.cancel();
        await simSub?.cancel();
      },
    );
    return controller.stream;
  }
}
