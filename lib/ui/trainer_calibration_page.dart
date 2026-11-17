import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/sensor_hub.dart';
import '../ble/trainer_calibration_store.dart';
import '../ble/trainer_learning.dart';
import '../ble/trainer_power_model.dart';

/// Corriger la puissance d'un vélo d'appartement imprécis.
///
/// Le cycliste règle une résistance, pédale à une cadence stable, lit la
/// puissance sur une référence (autre capteur, tableau du constructeur…) et
/// l'entre ici : l'appli retient « ce niveau, cette cadence, tant de watts ».
/// Quelques relevés à des niveaux et cadences différents suffisent pour que
/// `TrainerPowerModel` estime le reste, sans se fier à la puissance du vélo.
class TrainerCalibrationPage extends StatefulWidget {
  const TrainerCalibrationPage({
    super.key,
    required this.hub,
    required this.store,
    required this.deviceId,
    required this.deviceName,
    this.usesResistance = true,
  });

  /// Faux pour un vélo sans FTMS (cardio / Cycling Power / CSC seulement) : pas
  /// de niveau de résistance à lire, la puissance se corrige par la cadence
  /// seule et tous les relevés tombent au niveau 0.
  final bool usesResistance;

  final SensorHub hub;
  final TrainerCalibrationStore store;
  final String deviceId;
  final String deviceName;

  @override
  State<TrainerCalibrationPage> createState() => _TrainerCalibrationPageState();
}

class _TrainerCalibrationPageState extends State<TrainerCalibrationPage> {
  final _watts = TextEditingController();
  final _learning = ValueNotifier<bool>(false);
  TrainerLearningSession _session = TrainerLearningSession();
  Timer? _learningTick;

  @override
  void dispose() {
    _stopLearning();
    _learning.dispose();
    _watts.dispose();
    super.dispose();
  }

  int? get _level => widget.usesResistance
      ? widget.hub.latestResistance.value
      : widget.store.manualLevelFor(widget.deviceId);

  void _startLearning() {
    _session = TrainerLearningSession();
    // Watts bruts du vélo : voir `SensorHub.bypassCalibration`.
    widget.hub.bypassCalibration = true;
    _learning.value = true;
    _learningTick?.cancel();
    _learningTick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _learningStep(),
    );
  }

  void _stopLearning() {
    _learningTick?.cancel();
    _learningTick = null;
    widget.hub.bypassCalibration = false;
    if (_learning.value) _learning.value = false;
  }

  Future<void> _learningStep() async {
    final level = _level;
    final plateau = _session.feed(
      level: level ?? -1,
      cadence: level == null ? null : widget.hub.latestCadence.value,
      watts: widget.hub.latestPower.value?.toDouble(),
    );
    if (plateau != null) {
      await widget.store.addPoint(widget.deviceId, plateau);
    }
    if (!mounted) return;
    if (_session.isComplete) {
      _stopLearning();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apprentissage terminé : assez de données à ce niveau.',
          ),
        ),
      );
    } else {
      // Le décompte et la jauge vivent dans la session, pas dans un notifier.
      setState(() {});
    }
  }

  Widget _learningCard(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _learning,
      builder: (context, active, _) {
        final done = _session.currentPlateaus.length;
        final target = _session.nextTarget;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apprentissage automatique',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  active
                      ? (_level == null
                            ? 'Aucune résistance reçue : pédalez pour que le '
                                  'vélo se manifeste.'
                            : 'Paliers trouvés : $done sur '
                                  '${_session.neededPlateaus}. '
                                  '${target == null ? '' : 'Visez ${target.round()} tr/min '}'
                                  'et tenez-la ${_session.plateauSamples} s.')
                      : 'Pédalez à plusieurs cadences, sans rien saisir : '
                            'l’appli repère les paliers tenus, retient la '
                            'médiane de chacun et s’arrête seule quand elle a '
                            'assez de données pour ce niveau. Elle apprend des '
                            'watts bruts du vélo, qu’elle lisse ensuite.',
                  style: theme.textTheme.bodySmall,
                ),
                if (active) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (_session.stableSamples / _session.plateauSamples)
                        .clamp(0.0, 1.0),
                  ),
                ],
                const SizedBox(height: 8),
                active
                    ? OutlinedButton(
                        onPressed: _stopLearning,
                        child: const Text('Arrêter'),
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.school_outlined),
                        onPressed: _startLearning,
                        label: const Text('Lancer l’apprentissage'),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addPoint() async {
    final resistance = widget.usesResistance
        ? widget.hub.latestResistance.value
        : widget.store.manualLevelFor(widget.deviceId);
    final cadence = widget.hub.latestCadence.value;
    final watts = double.tryParse(_watts.text.trim().replaceAll(',', '.'));
    if (resistance == null || cadence == null || cadence <= 0) return;
    if (watts == null || watts <= 0) return;

    await widget.store.addPoint(
      widget.deviceId,
      TrainerCalibrationPoint(
        resistance: resistance,
        cadence: cadence,
        watts: watts,
      ),
    );
    _watts.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Relevé ajouté : '
          'niveau $resistance, '
          '${cadence.round()} tr/min, ${watts.round()} W',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.usesResistance
              ? 'Calibrer le home-trainer'
              : 'Calibrer selon frein et cadence',
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final points = store.pointsFor(widget.deviceId);
          final levels = TrainerPowerModel(points).calibratedLevels;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.deviceName.isEmpty ? 'Home-trainer' : widget.deviceName,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Utiliser la puissance estimée'),
                subtitle: Text(
                  points.isEmpty
                      ? 'Ajoutez au moins un relevé pour l’activer.'
                      : 'Remplace les watts du vélo par l’estimation.',
                ),
                value: store.enabledFor(widget.deviceId),
                onChanged: points.isEmpty
                    ? null
                    : (value) => store.setEnabled(widget.deviceId, value),
              ),
              if (!widget.usesResistance) ...[
                // Le vélo ne publie pas son frein : on le dit ici, et c'est
                // ce niveau qui range les relevés et choisit la courbe.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Niveau du frein'),
                  subtitle: const Text(
                    'Celui de la molette du vélo. Changez-le ici dès que '
                    'vous la tournez.',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Niveau moins un',
                        onPressed: () => store.setManualLevel(
                          widget.deviceId,
                          store.manualLevelFor(widget.deviceId) - 1,
                        ),
                      ),
                      Text(
                        '${store.manualLevelFor(widget.deviceId)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Niveau plus un',
                        onPressed: () => store.setManualLevel(
                          widget.deviceId,
                          store.manualLevelFor(widget.deviceId) + 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              _learningCard(context),
              const Divider(),
              Text('En direct', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: Listenable.merge([
                  hub.latestResistance,
                  hub.latestCadence,
                  hub.latestPower,
                ]),
                builder: (context, _) => Row(
                  children: [
                    _Reading(
                      widget.usesResistance ? 'Résistance' : 'Frein',
                      widget.usesResistance
                          ? hub.latestResistance.value
                          : store.manualLevelFor(widget.deviceId),
                      '',
                    ),
                    _Reading(
                      'Cadence',
                      hub.latestCadence.value?.round(),
                      ' tr/min',
                    ),
                    _Reading('Puissance', hub.latestPower.value, ' W'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ajouter un relevé',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                widget.usesResistance
                    ? 'Réglez une résistance, pédalez à cadence stable, puis '
                          'entrez la puissance lue sur votre référence. Variez le '
                          'niveau et la cadence d’un relevé à l’autre.'
                    : 'Pédalez à cadence stable, puis entrez la puissance lue '
                          'sur votre référence. Variez la cadence d’un relevé à '
                          'l’autre : deux relevés suffisent pour ajuster la '
                          'courbe, un seul suppose que la puissance suit la '
                          'cadence.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _watts,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Puissance de référence (W)',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addPoint(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _addPoint,
                    child: const Text('Ajouter'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ValueListenableBuilder<int?>(
                valueListenable: hub.latestResistance,
                builder: (context, resistance, _) =>
                    widget.usesResistance && resistance == null
                    ? Text(
                        'Aucune résistance reçue : le vélo n’expose pas '
                        'FTMS, ou il ne pédale pas encore.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const Divider(height: 32),
              Text(
                'Relevés (${points.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (levels.isNotEmpty)
                Text(
                  levels.length == 1
                      ? 'Niveau calibré : ${levels.first}. Les autres niveaux '
                            'utilisent celui-ci.'
                      : 'Niveaux calibrés : ${levels.first} à ${levels.last}. '
                            'Au-delà, l’estimation reste sur le niveau le plus '
                            'proche.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              for (final point in points)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Niveau ${point.resistance} · '
                    '${point.cadence.round()} tr/min',
                  ),
                  subtitle: Text('${point.watts.round()} W'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Supprimer ce relevé',
                    onPressed: () => store.removePoint(widget.deviceId, point),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading(this.label, this.value, this.unit);

  final String label;
  final int? value;
  final String unit;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        // `—` et jamais `0` : un zéro se lirait comme une mesure.
        Text(
          value == null ? '—' : '$value$unit',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    ),
  );
}
