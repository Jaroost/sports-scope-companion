import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'decoders/di2.dart';
import 'primary_source_gate.dart';
import 'samples.dart';
import 'sensor_connection.dart';
import 'sensor_profile.dart';
import 'trainer_calibration_store.dart';

/// Agrège plusieurs capteurs en un seul flux d'échantillons.
///
/// Le hub ne fait que router : il ne décide ni de l'enregistrement ni de
/// l'affichage. La couche session s'abonne à [samples] et écrit sur disque
/// *avant* que l'UI ne lise [latest…] — un crash ne doit jamais coûter une
/// sortie.
class SensorHub {
  SensorHub({
    String? Function()? primaryHeartRateOf,
    this.trainerCalibration,
  }) : _primaryHeartRateOf = primaryHeartRateOf ?? (() => null);

  /// Les relevés qui corrigent la puissance d'un vélo d'appartement imprécis
  /// (`null` : aucune correction, comme avant).
  final TrainerCalibrationStore? trainerCalibration;

  /// L'appareil désigné « cardio principal » (`KnownDevice.primaryHeartRate`).
  /// Une fonction et non une valeur : il se choisit sur la page des capteurs,
  /// pendant que le hub tourne déjà.
  final String? Function() _primaryHeartRateOf;
  final _heartRateGate = PrimarySourceGate();

  final _connections = <SensorConnection>[];
  final _samples = StreamController<SensorSample>.broadcast();
  final _rawFrames = StreamController<RawFrame>.broadcast();

  Stream<SensorSample> get samples => _samples.stream;
  Stream<RawFrame> get rawFrames => _rawFrames.stream;

  List<SensorConnection> get connections => List.unmodifiable(_connections);

  // Dernières valeurs connues, pour l'affichage.
  final latestHeartRate = ValueNotifier<int?>(null);
  final latestPower = ValueNotifier<int?>(null);
  final latestPowerBalance = ValueNotifier<double?>(null);
  final latestCadence = ValueNotifier<double?>(null);
  final latestGears = ValueNotifier<Di2Gears?>(null);

  /// Vitesse (m/s) et niveau de résistance donnés par un home-trainer FTMS.
  /// Même péremption que les autres mesures : une machine qui s'arrête ne doit
  /// pas laisser un niveau figé à l'écran.
  final latestTrainerSpeedMps = ValueNotifier<double?>(null);
  final latestResistance = ValueNotifier<int?>(null);

  /// Au-delà, une mesure affichée est retirée (`—` à l'écran). Sans ça, le hub
  /// gardait la dernière valeur d'un capteur muet — montre qui a cessé de
  /// diffuser, ceinture qui glisse — et un pouls figé se lisait comme du
  /// direct. Un peu plus court que `RideRecorder.sensorTtl` (10 s) : l'écran ne
  /// doit jamais montrer une valeur que la trace a déjà abandonnée. La position
  /// Di2 n'expire pas (un braquet reste engagé), et le radar a sa propre
  /// péremption (`radarViewFor`).
  static const displayTtl = Duration(seconds: 8);

  Timer? _expiryTimer;
  DateTime? _heartRateAt;
  DateTime? _powerAt;
  DateTime? _cadenceAt;
  DateTime? _trainerSpeedAt;
  DateTime? _resistanceAt;

  /// Dernier état du radar. `null` = pas de radar connecté ; un [RadarSample]
  /// vide = route dégagée. La distinction compte : on n'affiche pas la même
  /// chose dans les deux cas.
  final latestRadar = ValueNotifier<RadarSample?>(null);

  /// Les connexions qui portent cette capacité, dans l'ordre d'ajout.
  ///
  /// Sur les capacités *détectées*, jamais sur ce que l'appareil annonçait au
  /// scan : c'est la découverte des services qui fait foi.
  List<SensorConnection> connectionsWith(SensorKind kind) => [
        for (final connection in _connections)
          if (connection.detectedKinds.value.contains(kind)) connection,
      ];

  /// Une connexion déjà ouverte vers cet appareil, s'il y en a une.
  SensorConnection? connectionFor(DeviceIdentifier remoteId) {
    for (final connection in _connections) {
      if (connection.device.remoteId == remoteId) return connection;
    }
    return null;
  }

  /// Ajoute un capteur et lance sa connexion.
  ///
  /// Ce qu'on lira dessus n'est pas passé en paramètre : la connexion découvre
  /// les capacités de l'appareil et se branche sur tous les profils reconnus
  /// (voir `sensor_profile.dart`). Ajouter un capteur au projet ne touche donc
  /// jamais à ce fichier.
  ///
  /// Redemander un appareil déjà présent renvoie la connexion existante : deux
  /// abonnements sur la même caractéristique doubleraient les échantillons.
  Future<SensorConnection> add(
    BluetoothDevice device, {
    String? label,
  }) async {
    final existing = connectionFor(device.remoteId);
    if (existing != null) return existing;

    final connection = SensorConnection(device: device, label: label);
    _connections.add(connection);

    connection.samples.listen((sample) => _onSample(connection, sample),
        onError: (Object e) {
      debugPrint('[hub] ${connection.name}: $e');
    });
    connection.rawFrames.listen(_rawFrames.add);

    await connection.start();
    return connection;
  }

  /// Remplace les watts d'un vélo d'appartement par l'estimation tirée de son
  /// niveau de résistance et de la cadence, si le cycliste l'a calibré et
  /// activé. Appliqué ici, **avant** `_samples` : l'enregistreur, le pont et
  /// l'écran voient tous la même puissance — pas seulement `latestPower`.
  ///
  /// On ne devine jamais : sans niveau de résistance ni cadence récents, la
  /// mesure du vélo passe telle quelle. Les trames brutes (donc le relais vers
  /// une montre) ne sont, elles, **pas** corrigées.
  SensorSample _calibrated(SensorConnection source, SensorSample sample) {
    if (sample is! PowerSample) return sample;
    final model =
        trainerCalibration?.modelFor(source.device.remoteId.str);
    // Un vélo sans FTMS ne publie pas son niveau de frein : le cycliste le dit à
    // la main (`manualLevelFor`, réglé sur la page de calibration). Un vélo FTMS
    // dont la résistance vient de se taire, lui, ne retombe pas sur ce niveau.
    final id = source.device.remoteId.str;
    final hasResistance =
        source.detectedKinds.value.contains(SensorKind.trainer);
    final resistance = latestResistance.value ??
        (hasResistance ? null : trainerCalibration?.manualLevelFor(id));
    final cadence = latestCadence.value;
    if (model == null || resistance == null || cadence == null) return sample;

    final watts = model.estimate(resistance: resistance, cadence: cadence);
    if (watts == null) return sample;
    return PowerSample(sample.at, watts.round(),
        balanceLeftPercent: sample.balanceLeftPercent);
  }

  void _onSample(SensorConnection source, SensorSample rawSample) {
    final sample = _calibrated(source, rawSample);
    // Filtré ici, avant `_samples` : l'enregistreur et le pont lisent ce flux,
    // pas `latestHeartRate`, et la relève doit valoir pour eux aussi. Les
    // trames brutes, elles, passent toutes — c'est l'outil de diagnostic.
    if (sample is HeartRateSample &&
        !_heartRateGate.accept(
          source: source.device.remoteId.str,
          primary: _primaryHeartRateOf(),
          at: sample.at,
          live: sample.bpm > 0,
        )) {
      return;
    }
    switch (sample) {
      case HeartRateSample(:final bpm):
        latestHeartRate.value = bpm;
        _heartRateAt = DateTime.now();
        _armExpiry();
      case PowerSample(:final watts, :final balanceLeftPercent):
        latestPower.value = watts;
        latestPowerBalance.value = balanceLeftPercent;
        _powerAt = DateTime.now();
        _armExpiry();
      case CadenceSample(:final rpm):
        latestCadence.value = rpm;
        _cadenceAt = DateTime.now();
        _armExpiry();
      case SpeedSample(:final metersPerSecond):
        latestTrainerSpeedMps.value = metersPerSecond;
        _trainerSpeedAt = DateTime.now();
        _armExpiry();
      case ResistanceSample(:final level):
        latestResistance.value = level;
        _resistanceAt = DateTime.now();
        _armExpiry();
      case GearSample(:final gears):
        latestGears.value = gears;
      case RemoteButtonSample():
        break; // une impulsion, rien à retenir ici — voir RideShellPage
      case RadarSample():
        latestRadar.value = sample;
      case WheelSpeedSample():
        break;
      case BatterySample():
        break; // par appareil — voir BatteryStatusNotifier, pas un scalaire du hub
    }
    _samples.add(sample);
  }

  /// Tic d'une seconde, allumé à la première mesure et éteint quand plus rien
  /// n'est affiché : un hub au repos ne réveille personne.
  void _armExpiry() {
    _expiryTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (_expired(_heartRateAt, now)) {
        latestHeartRate.value = null;
        _heartRateAt = null;
      }
      if (_expired(_powerAt, now)) {
        latestPower.value = null;
        latestPowerBalance.value = null;
        _powerAt = null;
      }
      if (_expired(_cadenceAt, now)) {
        latestCadence.value = null;
        _cadenceAt = null;
      }
      if (_expired(_trainerSpeedAt, now)) {
        latestTrainerSpeedMps.value = null;
        _trainerSpeedAt = null;
      }
      if (_expired(_resistanceAt, now)) {
        latestResistance.value = null;
        _resistanceAt = null;
      }
      if (_heartRateAt == null &&
          _powerAt == null &&
          _cadenceAt == null &&
          _trainerSpeedAt == null &&
          _resistanceAt == null) {
        _expiryTimer?.cancel();
        _expiryTimer = null;
      }
    });
  }

  static bool _expired(DateTime? at, DateTime now) =>
      at != null && now.difference(at) > displayTtl;

  /// Ferme la connexion à un appareil et cesse de le suivre.
  ///
  /// Les dernières valeurs affichées ne sont pas remises à zéro sur-le-champ :
  /// elles expirent d'elles-mêmes au bout de [displayTtl].
  Future<void> remove(DeviceIdentifier remoteId) async {
    final connection = connectionFor(remoteId);
    if (connection == null) return;
    _connections.remove(connection);
    await connection.dispose();
  }

  Future<void> dispose() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    for (final connection in _connections) {
      await connection.dispose();
    }
    _connections.clear();
    await _samples.close();
    await _rawFrames.close();
  }
}
