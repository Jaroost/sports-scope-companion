import 'package:flutter/material.dart';

import '../../ble/sensor_hub.dart';
import '../../dashboard/dashboard_block.dart';
import 'block_card.dart';

/// Le niveau du frein d'un vélo d'appartement, avec de quoi le changer.
///
/// Le vélo ne le publie pas (pas de FTMS) : c'est le cycliste qui le dit, et la
/// correction de puissance par cadence s'appuie dessus — voir
/// `TrainerCalibrationStore.manualLevelFor`. Il se règle ici parce que c'est en
/// tournant la molette qu'on le change, pas sur une page de réglages.
///
/// Sans vélo de ce genre, le niveau s'écrit `—` et les boutons sont inertes :
/// un zéro se lirait comme un niveau.
class BrakeLevelControl extends StatelessWidget {
  const BrakeLevelControl({
    super.key,
    required this.hub,
    this.mode = BrakeLevelMode.full,
    this.color,
    this.textColor,
  });

  final SensorHub hub;
  final BrakeLevelMode mode;
  final Color? color;
  final Color? textColor;

  /// La largeur à laquelle le bloc se construit avant mise à l'échelle
  /// (`ScaleToFit` la ramène à la case), comme [DashboardActionButton].
  static const _fullWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    final store = hub.trainerCalibration;
    // La découverte des services finit après la connexion : sans l'écouter, le
    // bloc resterait sur `—` alors que le vélo répond.
    final listenable = Listenable.merge([
      if (store != null) store,
      for (final connection in hub.connections) ...[
        connection.detectedKinds,
        connection.status,
      ],
    ]);

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final id = hub.brakeConnection?.device.remoteId.str;
        final level = id == null || store == null
            ? null
            : store.manualLevelFor(id);
        void change(int delta) {
          if (id == null || store == null || level == null) return;
          store.setManualLevel(id, level + delta);
        }

        final fg = textColor ?? Colors.white;
        final compact = mode == BrakeLevelMode.compact;

        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              iconSize: compact ? 20 : 32,
              tooltip: 'Frein moins un',
              icon: const Icon(Icons.remove),
              onPressed: level == null ? null : () => change(-1),
            ),
            SizedBox(
              width: compact ? 56 : 72,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Frein',
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: compact ? 11 : 13,
                    ),
                  ),
                  // `—` et jamais `0` : un zéro se lirait comme un niveau.
                  Text(
                    level == null ? '—' : '$level',
                    style: TextStyle(
                      color: fg,
                      fontSize: compact ? 24 : 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              iconSize: compact ? 20 : 32,
              tooltip: 'Frein plus un',
              icon: const Icon(Icons.add),
              onPressed: level == null ? null : () => change(1),
            ),
          ],
        );

        return BlockSurface(
          background: color,
          child: compact
              ? row
              : SizedBox(
                  width: _fullWidth,
                  child: Center(child: row),
                ),
        );
      },
    );
  }
}
