import 'package:flutter/material.dart';

import '../dashboard/companion_settings_store.dart';
import '../dashboard/preset_picker.dart';
import '../ui/formats.dart';
import 'training_program.dart';
import 'training_program_catalog_fetch.dart';
import 'training_program_catalog_store.dart';
import 'training_program_fetch.dart';
import 'training_program_summary.dart';

/// Choisir un programme d'entraînement — même patron que
/// `NavigationPickerSheet` : la liste s'affiche depuis le cache avant que le
/// réseau ait répondu, pour rester utilisable au départ comme en pleine
/// sortie, sac au dos, sans 4G.
///
/// La feuille **rend un [TrainingProgram] complet**, pas un résumé : le
/// catalogue ne porte que les résumés (`/api/training_programs` sert des
/// sommaires, pas les jalons), donc le choix d'une ligne va d'abord résoudre
/// le programme complet par jeton de partage (même endpoint public que le
/// lien de navigation, `fetchSharedTrainingProgram`) avant de se refermer.
class WorkoutPickerSheet extends StatefulWidget {
  const WorkoutPickerSheet({
    super.key,
    required this.catalog,
    this.settings,
    this.fetch = const TrainingProgramCatalogFetch(),
  });

  final TrainingProgramCatalogStore catalog;

  /// Les profils de sortie, pour **choisir celui qui part** depuis cette feuille — le même
  /// que dans `NavigationPickerSheet`. `null` : pas de ligne de profil.
  final CompanionSettingsStore? settings;
  final TrainingProgramCatalogFetch fetch;

  @override
  State<WorkoutPickerSheet> createState() => _WorkoutPickerSheetState();
}

class _WorkoutPickerSheetState extends State<WorkoutPickerSheet> {
  TrainingProgramFetchStatus? _status;
  bool _refreshing = false;

  /// Le jeton en cours de résolution — désactive sa ligne le temps du fetch,
  /// pour éviter un double tap qui ouvrirait deux fois la même feuille.
  String? _resolving;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final result = await widget.fetch.run();
    if (result.status == TrainingProgramFetchStatus.ok) {
      await widget.catalog.record(result.programs);
    }
    if (!mounted) return;
    setState(() {
      _status = result.status;
      _refreshing = false;
    });
  }

  Future<void> _pick(TrainingProgramSummary summary) async {
    setState(() => _resolving = summary.shareToken);
    final program = await fetchSharedTrainingProgram(summary.shareToken);
    if (!mounted) return;
    if (program == null) {
      setState(() => _resolving = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Programme injoignable — réessaie une fois connecté.'),
      ));
      return;
    }
    Navigator.of(context).pop(program);
  }

  /// Changer de profil sans quitter le sélecteur : la feuille de choix se pose par-dessus
  /// celle-ci. Même geste que `NavigationPickerSheet._changePreset`.
  Future<void> _changePreset() async {
    await choosePreset(context, widget.settings!);
    if (mounted) setState(() {});
  }

  /// Le profil qui va partir, en tête. Paraît **seulement s'il y a un choix** (plus d'un
  /// profil) : à une seule entrée, la ligne ne serait que du bruit — même seuil que
  /// `NavigationPickerSheet`. À l'écoute du magasin : un rafraîchissement des profils lancé
  /// à l'ouverture (`_HomePageState._syncProfiles`) met la ligne à jour.
  Widget _presetTile() {
    final settings = widget.settings!;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        if (!settings.hasChoice) return const SizedBox.shrink();
        final preset = settings.preset;
        return Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: presetLeading(preset),
              title: Text(preset.name),
              subtitle: Text(describePreset(preset)),
              trailing: const Icon(Icons.unfold_more),
              onTap: _changePreset,
            ),
            const Divider(),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final programs = widget.catalog.programs;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.settings != null) _presetTile(),
          _header(),
          _notice(),
          Flexible(
            child: programs.isEmpty
                ? _emptyMessage()
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: programs.length,
                      itemBuilder: (context, i) => _programTile(programs[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Mes programmes d\'entraînement',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (_refreshing)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _notice() {
    final message = switch (_status) {
      TrainingProgramFetchStatus.signedOut =>
        'Pas connecté : ouvre l\'écran Compte pour retrouver tes programmes.',
      TrainingProgramFetchStatus.failed when widget.catalog.updatedAt != null =>
        'Site injoignable — liste du '
            '${formatDateTime(widget.catalog.updatedAt!)}.',
      TrainingProgramFetchStatus.failed => 'Site injoignable.',
      _ => null,
    };

    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        message,
        style: const TextStyle(color: Colors.orange, fontSize: 12),
      ),
    );
  }

  Widget _emptyMessage() {
    final message = switch (_status) {
      null => 'Chargement…',
      TrainingProgramFetchStatus.ok => 'Aucun programme enregistré sur le site.',
      _ => 'Rien en mémoire pour l\'instant.',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(message, style: const TextStyle(color: Colors.grey)),
    );
  }

  Widget _programTile(TrainingProgramSummary program) {
    final resolving = _resolving == program.shareToken;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: resolving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.timer_outlined),
      title: Text(program.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatDuration(Duration(seconds: program.durationSeconds))} · '
        '${program.segmentCount} bloc${program.segmentCount > 1 ? 's' : ''}',
      ),
      enabled: _resolving == null,
      onTap: () => _pick(program),
    );
  }
}
