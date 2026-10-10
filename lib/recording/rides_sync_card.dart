import 'package:flutter/material.dart';

import 'ride_recorder.dart';
import 'ride_session.dart';
import 'ride_store.dart';
import 'ride_sync.dart';

/// « Mes sorties : x/y synchronisées » sur l'accueil, avec de quoi envoyer le reste d'un tap.
///
/// Compte les sorties **qui ont des points** et ne roulent plus ([syncableRides]) : x celles déjà
/// parties sur le site, y toutes. Un tap sur la carte ouvre « Mes sorties » ([onOpen]) ; le bouton
/// envoie ce qui manque, avec un seul choix de sport pour le lot.
///
/// Relit le disque quand l'enregistrement démarre ou s'arrête (une sortie vient d'apparaître), et
/// quand [refreshToken] change — l'accueil l'incrémente au retour de « Mes sorties », où l'on a pu
/// envoyer ou supprimer.
class RidesSyncCard extends StatefulWidget {
  const RidesSyncCard({
    super.key,
    required this.store,
    required this.recorder,
    required this.onOpen,
    this.refreshToken = 0,
  });

  final RideStore store;
  final RideRecorder recorder;
  final VoidCallback onOpen;
  final int refreshToken;

  @override
  State<RidesSyncCard> createState() => _RidesSyncCardState();
}

class _RidesSyncCardState extends State<RidesSyncCard> {
  List<RideSession>? _sessions;
  double? _progress;
  late bool _wasActive;

  @override
  void initState() {
    super.initState();
    _wasActive = widget.recorder.isActive;
    widget.recorder.addListener(_onRecorder);
    _reload();
  }

  @override
  void didUpdateWidget(RidesSyncCard old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _reload();
  }

  @override
  void dispose() {
    widget.recorder.removeListener(_onRecorder);
    super.dispose();
  }

  /// Une sortie qui démarre ou s'arrête change ce qu'il y a sur le disque.
  void _onRecorder() {
    final active = widget.recorder.isActive;
    if (active == _wasActive) return;
    _wasActive = active;
    _reload();
  }

  Future<void> _reload() async {
    final sessions = await widget.store.list();
    if (mounted) setState(() => _sessions = sessions);
  }

  Future<void> _sync(List<RideSession> pending) async {
    final sport = await pickRideSport(
      context,
      title: pending.length > 1 ? 'Sport de ces ${pending.length} sorties' : 'Sport de cette sortie',
    );
    if (sport == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _progress = 0);
    final report = await syncRides(
      store: widget.store,
      pending: pending,
      sport: sport,
      onProgress: (done, total) {
        if (mounted) setState(() => _progress = total == 0 ? 1 : done / total);
      },
    );
    if (!mounted) return;
    setState(() => _progress = null);
    await _reload();
    messenger.showSnackBar(SnackBar(content: Text(report.message)));
  }

  @override
  Widget build(BuildContext context) {
    final all = syncableRides(_sessions ?? const [], activeId: widget.recorder.session?.id);
    // Rien à compter : pas de carte plutôt qu'un « 0/0 » qui ne dit rien.
    if (all.isEmpty) return const SizedBox.shrink();

    final pending = pendingRides(all);
    final done = all.length - pending.length;
    final syncing = _progress != null;

    return Card(
      child: ListTile(
        onTap: widget.onOpen,
        leading: Icon(
          pending.isEmpty ? Icons.cloud_done : Icons.cloud_upload,
          color: pending.isEmpty ? Colors.teal : null,
        ),
        title: Text('Mes sorties : $done/${all.length} synchronisées'),
        subtitle: syncing
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              )
            : Text(pending.isEmpty
                ? 'Tout est sur le site.'
                : '${pending.length} à envoyer sur le site.'),
        trailing: pending.isEmpty
            ? const Icon(Icons.chevron_right)
            : FilledButton.tonal(
                onPressed: syncing ? null : () => _sync(pending),
                child: const Text('Synchroniser'),
              ),
      ),
    );
  }
}
