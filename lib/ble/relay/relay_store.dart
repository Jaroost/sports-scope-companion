import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../sensor_profile.dart';
import 'relay_gate.dart';

/// Le réglage du relais : allumé ou non, et **quelles informations** il laisse
/// passer.
///
/// C'est un geste local du cycliste (quel appareil de poignet il porte
/// aujourd'hui), pas une donnée du compte : il ne passe donc pas par les profils
/// de sortie du site. Même forme que les autres magasins — un JSON réécrit en
/// entier via un temporaire renommé.
class RelayStore extends ChangeNotifier {
  RelayStore(this._file);

  static Future<RelayStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store = RelayStore(File(p.join(directory.path, _fileName)));
    await store.load();
    return store;
  }

  static const _fileName = 'relay_settings.json';

  final File _file;

  /// **Éteint par défaut**, et rien n'est annoncé en Bluetooth tant que le
  /// cycliste ne l'a pas demandé : se rendre visible de tout ce qui passe n'est
  /// pas un comportement qu'on active en silence.
  bool _enabled = false;

  /// Absent vaut tout : une fois le relais voulu, c'est la montre qui choisit
  /// ce qu'elle lit — le cycliste décoche ce qu'il ne veut pas lui donner.
  Set<SensorKind> _kinds = {...relayableKinds};

  bool get enabled => _enabled;
  Set<SensorKind> get kinds => Set.unmodifiable(_kinds);
  bool allows(SensorKind kind) => _kinds.contains(kind);

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          _enabled = decoded['enabled'] == true;
          final raw = decoded['kinds'];
          if (raw is List) {
            _kinds = {
              for (final kind in relayableKinds)
                if (raw.contains(kind.name)) kind,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('[relais] réglage illisible, ignoré : $e');
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    await _write();
  }

  Future<void> setKind(SensorKind kind, bool value) async {
    if (!relayableKinds.contains(kind)) return;
    final changed = value ? _kinds.add(kind) : _kinds.remove(kind);
    if (!changed) return;
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    try {
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(jsonEncode({
        'enabled': _enabled,
        'kinds': [for (final kind in relayableKinds) if (_kinds.contains(kind)) kind.name],
      }));
      await temp.rename(_file.path);
    } catch (e) {
      debugPrint('[relais] écriture impossible : $e');
    }
  }
}
