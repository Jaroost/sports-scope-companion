import 'package:flutter/material.dart';

import '../ble/relay/ble_relay.dart';
import '../ble/relay/relay_gate.dart';
import '../ble/relay/relay_store.dart';
import '../ble/sensor_profile.dart';

/// Le relais Bluetooth : le téléphone se présente comme un capteur à une montre
/// qui n'arrive pas à se connecter au vrai, et lui rediffuse ce qu'il reçoit.
///
/// Une case par information : on peut donner la puissance à la montre sans lui
/// confier le cardio (qu'elle mesure elle-même au poignet, par exemple).
class RelayCard extends StatelessWidget {
  const RelayCard({super.key, required this.relay, required this.settings});

  final BleRelay relay;
  final RelayStore settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([relay, settings]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final status = relay.error ??
            (!settings.enabled
                ? 'Éteint'
                : relay.running
                    ? (relay.subscribers == 0
                        ? 'Visible — en attente de la montre'
                        : 'Relais actif · ${relay.subscribers} appareil(s) connecté(s)')
                    : 'Démarrage…');
        return Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.cell_tower),
                title: const Text('Relais vers une montre'),
                subtitle: Text(
                  status,
                  style: relay.error != null
                      ? TextStyle(color: theme.colorScheme.error)
                      : null,
                ),
                value: settings.enabled,
                onChanged: settings.setEnabled,
              ),
              if (settings.enabled) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sur la montre : ajouter un capteur, puis choisir ce '
                      'téléphone. Informations relayées :',
                    ),
                  ),
                ),
                for (final kind in relayableKinds)
                  CheckboxListTile(
                    dense: true,
                    title: Text(labelFor(kind)),
                    subtitle: kind == SensorKind.power
                        ? const Text('Comprend la cadence si le capteur la '
                            'joint à la puissance')
                        : null,
                    value: settings.allows(kind),
                    onChanged: (v) => settings.setKind(kind, v ?? false),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
