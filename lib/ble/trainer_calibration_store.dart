import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'trainer_power_model.dart';

/// Les relevés de calibration des home-trainers, par appareil, sur disque.
///
/// Par appareil (`remoteId`) et non global : la correction décrit *ce* vélo, et
/// un second boîtier n'a pas à hériter de la courbe du premier. Même patron que
/// `KnownDevicesStore` : en mémoire pour l'UI, le disque n'est qu'une copie
/// réécrite en entier via un temporaire renommé.
class TrainerCalibrationStore extends ChangeNotifier {
  TrainerCalibrationStore(this._file);

  static Future<TrainerCalibrationStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store =
        TrainerCalibrationStore(File(p.join(directory.path, _fileName)));
    await store.load();
    return store;
  }

  static const _fileName = 'trainer_calibration.json';

  final File _file;
  final _entries = <String, _Entry>{};
  final _models = <String, TrainerPowerModel>{};

  /// Même file d'écriture que `KnownDevicesStore` : deux écritures parallèles se
  /// disputeraient le fichier temporaire.
  Future<void> _writing = Future<void>.value();

  List<TrainerCalibrationPoint> pointsFor(String deviceId) =>
      List.unmodifiable(_entries[deviceId]?.points ?? const []);

  /// Faut-il corriger la puissance de cet appareil ? Faux par défaut : tant que
  /// le cycliste n'a pas relevé de points et dit oui, rien ne change.
  bool enabledFor(String deviceId) => _entries[deviceId]?.enabled ?? false;

  /// Le modèle à appliquer, ou `null` s'il n'y a rien à corriger (désactivé, ou
  /// aucun relevé). Mis en cache : le hub l'interroge à chaque trame.
  TrainerPowerModel? modelFor(String deviceId) {
    final entry = _entries[deviceId];
    if (entry == null || !entry.enabled || entry.points.isEmpty) return null;
    return _models.putIfAbsent(
        deviceId, () => TrainerPowerModel(entry.points));
  }

  /// Ajoute un relevé. Un relevé au même niveau et à moins de 1 tr/min d'un
  /// existant le **remplace** : refaire la mesure corrige, ne double pas.
  Future<void> addPoint(String deviceId, TrainerCalibrationPoint point) {
    final entry = _entries.putIfAbsent(deviceId, _Entry.new);
    entry.points.removeWhere((existing) =>
        existing.resistance == point.resistance &&
        (existing.cadence - point.cadence).abs() < 1);
    entry.points.add(point);
    entry.points.sort(_byLevelThenCadence);
    return _changed(deviceId);
  }

  Future<void> removePoint(String deviceId, TrainerCalibrationPoint point) {
    _entries[deviceId]?.points.remove(point);
    return _changed(deviceId);
  }

  Future<void> setEnabled(String deviceId, bool enabled) {
    _entries.putIfAbsent(deviceId, _Entry.new).enabled = enabled;
    return _changed(deviceId);
  }

  static int _byLevelThenCadence(
      TrainerCalibrationPoint a, TrainerCalibrationPoint b) {
    final level = a.resistance.compareTo(b.resistance);
    return level != 0 ? level : a.cadence.compareTo(b.cadence);
  }

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (entry.key is! String || value is! Map) continue;
        final points = value['points'];
        _entries[entry.key as String] = _Entry()
          ..enabled = value['enabled'] == true
          ..points.addAll([
            if (points is List)
              for (final raw in points)
                if (TrainerCalibrationPoint.fromJson(raw) case final point?)
                  point,
          ])
          ..points.sort(_byLevelThenCadence);
      }
    } catch (e) {
      // Fichier tronqué ou d'une autre version : on repart sans correction, qui
      // est l'état d'avant. Le fichier reste inspectable jusqu'à la prochaine
      // écriture.
      debugPrint('[trainer] calibration illisible, ignorée : $e');
      _entries.clear();
    }
    notifyListeners();
  }

  Future<void> _changed(String deviceId) async {
    _models.remove(deviceId);
    notifyListeners();
    final snapshot = {
      for (final entry in _entries.entries) entry.key: entry.value.toJson(),
    };
    _writing = _writing.then((_) => _write(snapshot));
    await _writing;
  }

  Future<void> _write(Map<String, Object> snapshot) async {
    try {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(jsonEncode(snapshot), flush: true);
      await temporary.rename(_file.path);
    } catch (e) {
      // Perdre la persistance ne doit pas faire tomber une sortie : la
      // calibration en mémoire reste juste jusqu'au prochain lancement.
      debugPrint('[trainer] écriture de la calibration impossible : $e');
    }
  }
}

class _Entry {
  var enabled = false;
  final points = <TrainerCalibrationPoint>[];

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'points': [for (final point in points) point.toJson()],
      };
}
