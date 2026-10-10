import 'package:flutter/material.dart';

import 'fit_writer.dart';
import 'ride_session.dart';
import 'ride_store.dart';
import 'ride_upload.dart';

/// Les sorties à envoyer : enregistrées avec des points, jamais envoyées, et pas celle qui
/// roule encore (elle grandit — on l'enverra une fois arrêtée).
List<RideSession> pendingRides(List<RideSession> sessions, {String? activeId}) => [
      for (final s in sessions)
        if (s.id != activeId && s.pointCount > 0 && !s.isSynced) s,
    ];

/// Combien de sorties comptent dans « x/y synchronisées » : les mêmes, envoyées ou non.
List<RideSession> syncableRides(List<RideSession> sessions, {String? activeId}) => [
      for (final s in sessions)
        if (s.id != activeId && s.pointCount > 0) s,
    ];

/// Ce qu'a donné un envoi groupé.
class RideSyncReport {
  const RideSyncReport({this.sent = 0, this.skipped = 0, this.stoppedBy});

  /// Sorties parties sur le site.
  final int sent;

  /// Sorties sans le moindre point lisible, laissées de côté.
  final int skipped;

  /// Ce qui a interrompu l'envoi (pas connecté, site injoignable) ; `null` si tout est passé.
  final RideUploadResult? stoppedBy;

  String get message {
    final noun = sent > 1 ? 'sorties envoyées' : 'sortie envoyée';
    final stop = stoppedBy;
    if (stop == null) return sent == 0 ? 'Rien à envoyer.' : '$sent $noun sur sports-scope.';
    final why = switch (stop.status) {
      RideUploadStatus.signedOut => 'Connecte-toi sur sports-scope (onglet Compte) avant d\'envoyer.',
      _ => 'Envoi interrompu${stop.message != null ? ' : ${stop.message}' : ' — site injoignable'}.',
    };
    return sent == 0 ? why : '$sent $noun. $why';
  }
}

/// Envoie [pending] sur le site, une par une, en notant chaque réussite sur le disque
/// ([RideStore.markSynced]) au fur et à mesure : un envoi coupé en route garde ce qui est déjà
/// parti, et le suivant reprend là.
///
/// S'arrête à **la première panne** (pas connecté, site injoignable) : continuer ferait attendre
/// le délai de chaque sortie restante pour le même échec.
Future<RideSyncReport> syncRides({
  required RideStore store,
  required List<RideSession> pending,
  required FitSport sport,
  void Function(int done, int total)? onProgress,
}) async {
  var sent = 0;
  var skipped = 0;
  for (var i = 0; i < pending.length; i++) {
    onProgress?.call(i, pending.length);
    final session = pending[i];
    try {
      final points = await store.points(session.id);
      final payload = buildRideUploadPayload(session: session, points: points, sport: sport);
      final result = await const RideUploadFetch().run(payload);
      if (result.status != RideUploadStatus.ok) {
        return RideSyncReport(sent: sent, skipped: skipped, stoppedBy: result);
      }
      await store.markSynced(session.id);
      sent++;
    } on EmptyRide {
      skipped++;
    }
  }
  onProgress?.call(pending.length, pending.length);
  return RideSyncReport(sent: sent, skipped: skipped);
}

/// Ce que la sortie était vraiment, pour le site comme pour le `.fit` — l'appli ne l'a jamais su
/// pendant l'enregistrement (voir `FitSport`). `null` si l'utilisateur ferme la boîte sans
/// choisir, ce qui annule plutôt que de deviner.
Future<FitSport?> pickRideSport(BuildContext context, {String title = 'Sport de cette sortie'}) =>
    showDialog<FitSport>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          _sportOption(dialogContext, FitSport.cycling, Icons.directions_bike),
          _sportOption(dialogContext, FitSport.mtb, Icons.terrain),
          _sportOption(dialogContext, FitSport.hiking, Icons.hiking),
        ],
      ),
    );

Widget _sportOption(BuildContext dialogContext, FitSport sport, IconData icon) => SimpleDialogOption(
      onPressed: () => Navigator.of(dialogContext).pop(sport),
      child: Row(children: [Icon(icon), const SizedBox(width: 12), Text(sport.label)]),
    );
