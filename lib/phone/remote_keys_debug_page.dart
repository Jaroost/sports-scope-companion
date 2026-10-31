import 'dart:async';

import 'package:flutter/material.dart';

import 'debug_log.dart';
import 'remote_keys.dart';

/// Banc d'essai de la télécommande Bluetooth : affiche chaque touche reçue, et
/// par quel chemin elle est arrivée. Temporaire, comme `GattSniffPage`.
///
/// Quatre chemins, qu'on veut distinguer avant de choisir lequel garder :
/// - `accessibility` : lecture/pause vue par le service d'accessibilité, avant
///   l'assistant — la seule voie qui livre l'appui long (sans lui, Gemini
///   s'ouvre) ; consommée là, la touche n'arrive plus par `media` ;
/// - `media` : la session média native (marche écran éteint) ;
/// - `volume` : le sens des pressions, via le fournisseur de volume — sans
///   appareil d'origine ;
/// - `activity` : la touche vue par la fenêtre avant son routage (appli au
///   premier plan, écran allumé seulement), avec **l'appareil qui l'a émise**.
///   C'est la sonde : appuyer sur le volume de la télécommande puis sur celui du
///   téléphone, et comparer les `id`/« nom » des deux lignes.
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

class _RemoteKeysDebugPageState extends State<RemoteKeysDebugPage>
    with WidgetsBindingObserver {
  final _entries = <String>[];
  StreamSubscription<RemoteKeyEvent>? _sub;
  bool? _accessibility;
  bool? _notificationAccess;
  RemoteKeyEvent? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = const AndroidRemoteKeys().events().listen(_record);
    unawaited(_refreshAccessibility());
    unawaited(_refreshNotificationAccess());
  }

  Future<void> _refreshNotificationAccess() async {
    final granted = await const AndroidRemoteKeys().notificationAccessGranted();
    if (mounted) setState(() => _notificationAccess = granted);
  }

  Future<void> _refreshAccessibility() async {
    final enabled = await const AndroidRemoteKeys().accessibilityEnabled();
    if (mounted) setState(() => _accessibility = enabled);
  }

  // On revient des réglages d'accessibilité : relire l'état du service.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAccessibility());
      unawaited(_refreshNotificationAccess());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _record(RemoteKeyEvent event) {
    final line = event.toString();
    DebugLog.instance.add('[télécommande] $line');
    if (!mounted) return;
    if (event.source == 'status') setState(() => _status = event);
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
          if (_notificationAccess == false)
            ListTile(
              dense: true,
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Reprise des touches à l’aveugle'),
              subtitle: const Text(
                  'Sans accès aux notifications, on ne sait pas si la session '
                  'reçoit les touches. Active « Sports Scope — télécommande ».'),
              trailing: TextButton(
                onPressed: () => const AndroidRemoteKeys()
                    .openNotificationAccessSettings(),
                child: const Text('Réglages'),
              ),
            )
          else if (_status case final status?)
            ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: const Text('Ordre des sessions (indicatif)'),
              subtitle: Text(
                  '${status.device ?? ''}\nAndroid route les touches vers '
                  'l’appli qui a démarré du son en dernier : seule une touche '
                  'reçue ici le prouve.'),
            ),
          if (_accessibility == false)
            ListTile(
              dense: true,
              leading: const Icon(Icons.accessibility_new),
              title: const Text('Appui long sur lecture/pause'),
              subtitle: const Text(
                  'Service d’accessibilité désactivé : l’appui long ouvre '
                  'l’assistant. Active « Sports Scope — télécommande ».'),
              trailing: TextButton(
                onPressed: () async {
                  await const AndroidRemoteKeys().openAccessibilitySettings();
                },
                child: const Text('Réglages'),
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
