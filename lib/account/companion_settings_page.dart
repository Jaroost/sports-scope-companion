import 'package:flutter/material.dart';

import '../dashboard/companion_settings_store.dart';
import 'companion_settings_write.dart';
import 'map_style_choice.dart';

/// Réglages globaux du compte (pas ceux d'un profil de sortie) : deviner un col
/// en navigation libre, et le fond de carte de la navigation guidée.
///
/// **Écrit par l'appli elle-même**, pas seulement par l'éditeur web — voir
/// `CompanionSettingsWrite` (document complet, fusionné côté site) et
/// `MapStyleWrite` (un seul champ, fusionné côté serveur) ; seul autre
/// précédent d'écriture depuis Dart : `RideUploadFetch`.
///
/// Le fond de carte se choisit aussi depuis le menu d'une page de sortie, en
/// roulant (`RideShellPage`, `NavigationWebController.setMapStyle`) — mais
/// celui-là agit sur la page déjà ouverte, en direct, et n'existe donc que
/// pendant une navigation. Cette ligne-ci reste le seul chemin hors sortie,
/// avant de partir : `NavControlsPanel`, qui le propose en navigateur, est
/// masqué dans l'appli (`appOwnsChrome`).
class CompanionSettingsPage extends StatefulWidget {
  const CompanionSettingsPage({super.key, required this.settings});

  final CompanionSettingsStore settings;

  @override
  State<CompanionSettingsPage> createState() => _CompanionSettingsPageState();
}

class _CompanionSettingsPageState extends State<CompanionSettingsPage> {
  bool _saving = false;

  Future<void> _setColDetection(bool value) async {
    // Le document brut du compte, PAS un document reconstruit : `sanitize` côté
    // site remplacerait tout par les préréglages d'usine si `presets` manquait.
    final document = widget.settings.rawDocument;
    if (document == null) {
      _snack('Aucun réglage reçu du site pour l\'instant — connecte-toi '
          '(bouton Compte) et réessaie.');
      return;
    }

    setState(() => _saving = true);
    final result = await const CompanionSettingsWrite().run({
      ...document,
      'col_detection': value,
    });
    if (!mounted) return;
    setState(() => _saving = false);

    switch (result.status) {
      case CompanionSettingsWriteStatus.ok:
        // Le document RENVOYÉ (assaini par le serveur), pas celui envoyé — même
        // contrat que l'éditeur web.
        await widget.settings.record(result.document);
      case CompanionSettingsWriteStatus.signedOut:
        _snack('Connecte-toi (bouton Compte) pour changer ce réglage.');
      case CompanionSettingsWriteStatus.failed:
        _snack('Échec de l\'enregistrement — réessaie avec du réseau.');
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('Détection de col en navigation libre'),
              subtitle: const Text(
                'En roulant sans itinéraire, devine — d\'après la pente et les '
                'cols connus alentour — que tu montes vers un col, et te '
                'l\'annonce brièvement.',
              ),
              value: widget.settings.colDetection,
              onChanged: _saving ? null : _setColDetection,
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Fond de carte de navigation'),
              subtitle: Text(mapStyleLabel(widget.settings)),
              onTap: _saving
                  ? null
                  : () => changeMapStyle(context, widget.settings, onBusy: (busy) {
                        if (mounted) setState(() => _saving = busy);
                      }),
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
