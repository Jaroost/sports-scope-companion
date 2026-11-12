import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../samples.dart';
import '../sensor_hub.dart';
import '../sensor_profile.dart';
import 'relay_gate.dart';
import 'relay_store.dart';

/// Le côté plateforme : un serveur GATT et une publicité (`BleRelay.kt`).
abstract class RelayPlatform {
  /// Annonce les services de [kinds] et accepte les connexions. Rend `null` si
  /// tout va bien, sinon la raison en une phrase (permission, Bluetooth éteint,
  /// publicité non supportée).
  Future<String?> start(Set<SensorKind> kinds);

  Future<void> stop();

  /// Pousse une trame aux abonnés de [characteristicUuid].
  Future<void> notify(String characteristicUuid, List<int> bytes);

  /// Nombre d'appareils (montre, compteur) actuellement abonnés.
  Stream<int> get subscribers;
}

class AndroidRelayPlatform implements RelayPlatform {
  static const _method = MethodChannel('sports_scope/relay');
  static const _events = EventChannel('sports_scope/relay/subscribers');

  @override
  Future<String?> start(Set<SensorKind> kinds) async {
    // Android 12+ : « Appareils à proximité ». Sur les versions plus anciennes
    // la demande est accordée d'office.
    final advertise = await Permission.bluetoothAdvertise.request();
    if (!advertise.isGranted && !advertise.isLimited) {
      return 'Autorise « Appareils à proximité » pour relayer';
    }
    try {
      return await _method.invokeMethod<String>(
          'start', [for (final k in kinds) k.name]);
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    } on MissingPluginException {
      return 'Relais indisponible sur cet appareil';
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  @override
  Future<void> notify(String characteristicUuid, List<int> bytes) async {
    try {
      await _method.invokeMethod<void>('notify', {
        'uuid': characteristicUuid,
        'value': Uint8List.fromList(bytes),
      });
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  @override
  Stream<int> get subscribers => _events
      .receiveBroadcastStream()
      .map((e) => e is int ? e : 0)
      .handleError((Object _) {});
}

/// Rediffuse en Bluetooth les trames des capteurs que le téléphone a réussi à
/// connecter, pour un récepteur qui n'y parvient pas (montre Garmin face à un
/// home-trainer qui n'accepte qu'une connexion).
///
/// On rediffuse les **trames brutes**, octets pour octets, et non des mesures
/// ré-encodées : la montre reçoit exactement ce que le capteur a dit (tours de
/// manivelle, équilibre, flags), sans que l'appli ait à en comprendre le
/// format. Conséquence assumée : le réglage porte sur une caractéristique
/// entière — la cadence que le capteur de puissance glisse *dans* sa trame de
/// puissance part avec elle.
class BleRelay extends ChangeNotifier {
  BleRelay({
    required this._hub,
    required this._store,
    RelayPlatform? platform,
  })  : _platform = platform ?? AndroidRelayPlatform() {
    _store.addListener(_sync);
    _sync();
  }

  final SensorHub _hub;
  final RelayStore _store;
  final RelayPlatform _platform;
  final _gate = RelayGate();

  StreamSubscription<RawFrame>? _frames;
  StreamSubscription<int>? _subs;
  bool _running = false;
  bool _starting = false;
  Set<SensorKind> _announced = const {};
  int _subscribers = 0;
  String? _error;
  bool _disposed = false;

  bool get running => _running;
  int get subscribers => _subscribers;

  /// Pourquoi le relais n'a pas pu démarrer, `null` sinon.
  String? get error => _error;

  Future<void> _sync() async {
    if (_starting) return;
    final wanted = _store.enabled ? _store.kinds : const <SensorKind>{};
    if (wanted.isEmpty) {
      await _stop();
      return;
    }
    if (_running && setEquals(wanted, _announced)) return;

    _starting = true;
    try {
      // Les services annoncés ne se changent pas à chaud : on repart de zéro.
      if (_running) await _stop();
      final problem = await _platform.start(wanted);
      _error = problem;
      if (problem != null) {
        notifyListeners();
        return;
      }
      _running = true;
      _announced = {...wanted};
      _gate.reset();
      _subs = _platform.subscribers.listen((n) {
        _subscribers = n;
        if (!_disposed) notifyListeners();
      });
      _frames = _hub.rawFrames.listen(_onFrame);
      notifyListeners();
    } finally {
      _starting = false;
    }
    // Un réglage changé pendant le démarrage ne doit pas être perdu.
    final now = _store.enabled ? _store.kinds : const <SensorKind>{};
    if (!setEquals(now, _running ? _announced : const <SensorKind>{})) {
      unawaited(_sync());
    }
  }

  void _onFrame(RawFrame frame) {
    final kind = relayKindOf(frame.characteristicUuid);
    if (kind == null || !_announced.contains(kind)) return;
    if (!_gate.accept(kind, frame.source, frame.at)) return;
    unawaited(_platform.notify(frame.characteristicUuid, frame.bytes));
  }

  Future<void> _stop() async {
    final wasRunning = _running;
    _running = false;
    _announced = const {};
    _subscribers = 0;
    await _frames?.cancel();
    await _subs?.cancel();
    _frames = null;
    _subs = null;
    if (wasRunning) await _platform.stop();
    _error = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _store.removeListener(_sync);
    unawaited(_stop());
    super.dispose();
  }
}
