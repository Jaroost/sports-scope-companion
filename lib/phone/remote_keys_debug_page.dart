import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debug_log.dart';
import 'remote_keys.dart';

/// Banc d'essai de la télécommande Bluetooth : affiche chaque touche reçue, et
/// par quel chemin elle est arrivée. Temporaire, comme `GattSniffPage`.
///
/// Trois chemins, qu'on veut distinguer avant de choisir lequel garder :
/// - `media` : la session média native (marche écran éteint) ;
/// - `volume` : le sens des pressions, via le fournisseur de volume ;
/// - `flutter` : la touche telle que la fenêtre la reçoit (appli au premier
///   plan seulement). Si une touche paraît ici **et** en `media`, c'est que la
///   session ne la consomme pas à elle seule.
///
/// L'écran n'est **pas** maintenu allumé, contrairement à `GattSniffPage` : le
/// cas à vérifier est justement écran verrouillé. Chaque touche est donc aussi
/// écrite dans le journal (menu Debug → Journal), qui se relit une fois le
/// téléphone déverrouillé.
class RemoteKeysDebugPage extends StatefulWidget {
  const RemoteKeysDebugPage({super.key});

  @override
  State<RemoteKeysDebugPage> createState() => _RemoteKeysDebugPageState();
}

class _RemoteKeysDebugPageState extends State<RemoteKeysDebugPage> {
  final _entries = <String>[];
  StreamSubscription<RemoteKeyEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = const AndroidRemoteKeys().events().listen(_record);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyRepeatEvent) return false;
    _record(RemoteKeyEvent(
      source: 'flutter',
      key: event.logicalKey.debugName ?? event.logicalKey.keyLabel,
      action: event is KeyDownEvent ? 'down' : 'up',
    ));
    // Jamais consommée : le banc observe, il ne vole rien.
    return false;
  }

  void _record(RemoteKeyEvent event) {
    final line = event.toString();
    DebugLog.instance.add('[télécommande] $line');
    if (!mounted) return;
    final now = DateTime.now();
    final stamp = '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    setState(() => _entries.insert(0, '$stamp  $line'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Télécommande (dev)'),
        actions: [
          IconButton(
            onPressed: () => setState(_entries.clear),
            icon: const Icon(Icons.clear_all),
            tooltip: 'Vider',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Appuie sur chaque bouton, appli au premier plan puis écran '
              'verrouillé. Tout est aussi écrit dans le journal.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('En attente d’une touche…'))
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 3),
                      child: Text(
                        _entries[i],
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
