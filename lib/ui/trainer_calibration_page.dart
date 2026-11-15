import 'package:flutter/material.dart';

import '../ble/sensor_hub.dart';
import '../ble/trainer_calibration_store.dart';
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
  });

  final SensorHub hub;
  final TrainerCalibrationStore store;
  final String deviceId;
  final String deviceName;

  @override
  State<TrainerCalibrationPage> createState() => _TrainerCalibrationPageState();
}

class _TrainerCalibrationPageState extends State<TrainerCalibrationPage> {
  final _watts = TextEditingController();

  @override
  void dispose() {
    _watts.dispose();
    super.dispose();
  }

  Future<void> _addPoint() async {
    final resistance = widget.hub.latestResistance.value;
    final cadence = widget.hub.latestCadence.value;
    final watts = double.tryParse(_watts.text.trim().replaceAll(',', '.'));
    if (resistance == null || cadence == null || cadence <= 0) return;
    if (watts == null || watts <= 0) return;

    await widget.store.addPoint(
      widget.deviceId,
      TrainerCalibrationPoint(
          resistance: resistance, cadence: cadence, watts: watts),
    );
    _watts.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Relevé ajouté : niveau $resistance, '
          '${cadence.round()} tr/min, ${watts.round()} W'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Calibrer le home-trainer')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final points = store.pointsFor(widget.deviceId);
          final levels = TrainerPowerModel(points).calibratedLevels;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.deviceName.isEmpty
                  ? 'Home-trainer'
                  : widget.deviceName),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Utiliser la puissance estimée'),
                subtitle: Text(points.isEmpty
                    ? 'Ajoutez au moins un relevé pour l’activer.'
                    : 'Remplace les watts du vélo par l’estimation.'),
                value: store.enabledFor(widget.deviceId),
                onChanged: points.isEmpty
                    ? null
                    : (value) => store.setEnabled(widget.deviceId, value),
              ),
              const Divider(),
              Text('En direct',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: Listenable.merge([
                  hub.latestResistance,
                  hub.latestCadence,
                  hub.latestPower,
                ]),
                builder: (context, _) => Row(
                  children: [
                    _Reading('Résistance', hub.latestResistance.value, ''),
                    _Reading(
                        'Cadence', hub.latestCadence.value?.round(), ' tr/min'),
                    _Reading('Puissance', hub.latestPower.value, ' W'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Ajouter un relevé',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Réglez une résistance, pédalez à cadence stable, puis entrez '
                'la puissance lue sur votre référence. Variez le niveau et la '
                'cadence d’un relevé à l’autre.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _watts,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
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
                builder: (context, resistance, _) => resistance == null
                    ? Text(
                        'Aucune résistance reçue : le vélo n’expose pas '
                        'FTMS, ou il ne pédale pas encore.',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      )
                    : const SizedBox.shrink(),
              ),
              const Divider(height: 32),
              Text('Relevés (${points.length})',
                  style: Theme.of(context).textTheme.titleMedium),
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
                  title: Text('Niveau ${point.resistance} · '
                      '${point.cadence.round()} tr/min'),
                  subtitle: Text('${point.watts.round()} W'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Supprimer ce relevé',
                    onPressed: () =>
                        store.removePoint(widget.deviceId, point),
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
            Text(value == null ? '—' : '$value$unit',
                style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );
}
