import 'package:flutter/material.dart';

import '../dashboard/companion_settings_store.dart';
import '../ui/map_style_picker.dart';
import 'map_style_write.dart';

/// Choisir le fond de carte de navigation et l'écrire sur le compte : la boîte de choix
/// ([pickMapStyle]), puis `MapStyleWrite`, puis le document en cache. Partagé entre l'accueil et
/// la page de réglages — une seule logique, plutôt que deux copies qui divergent.
///
/// [onBusy] : vrai pendant l'écriture (le temps d'un aller-retour par un WebView hors écran),
/// pour que l'appelant montre son attente à sa façon.
Future<void> changeMapStyle(
  BuildContext context,
  CompanionSettingsStore settings, {
  required ValueChanged<bool> onBusy,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

  // La liste vient du document en cache — vide contre un site plus ancien que ce réglage : on le
  // dit plutôt que d'ouvrir une boîte sans rien dedans.
  final styles = settings.mapStyles;
  if (styles.isEmpty) {
    snack('Réglage pas encore disponible — connecte-toi (bouton Compte) et relance l\'appli.');
    return;
  }

  final current = settings.mapStyle;
  final chosen = await pickMapStyle(context, styles: styles, current: current);
  if (chosen == null || chosen == current) return;

  onBusy(true);
  final result = await const MapStyleWrite().run(chosen);
  onBusy(false);

  switch (result.status) {
    case MapStyleWriteStatus.ok:
      // Le fond RENVOYÉ (celui que le serveur a retenu), pas celui envoyé.
      if (result.id != null) await settings.recordMapStyle(result.id!);
    case MapStyleWriteStatus.signedOut:
      snack('Connecte-toi (bouton Compte) pour changer ce réglage.');
    case MapStyleWriteStatus.failed:
      snack('Échec de l\'enregistrement — réessaie avec du réseau.');
  }
}

/// Libellé du fond choisi. Repli sur l'id brut si le catalogue ne le connaît pas encore
/// (document tout juste arrivé, un site plus récent a ajouté ce fond) plutôt que de le taire.
String mapStyleLabel(CompanionSettingsStore settings) {
  final id = settings.mapStyle;
  if (id == null) return 'Pas encore reçu du site';
  for (final style in settings.mapStyles) {
    if (style.id == id) return style.label;
  }
  return id;
}
