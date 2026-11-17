import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Distance du glissé, comme sur le minuteur (`_SwipeControls`) : voulu, mais
  /// on le fait au guidon.
  static const _swipeThreshold = 50.0;

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

        return _Swipe(
          threshold: _swipeThreshold,
          // Vers la gauche on réduit, vers la droite on augmente : même sens
          // que le minuteur, où la droite « remet à zéro ».
          onLeft: level == null ? null : () => change(-1),
          onRight: level == null ? null : () => change(1),
          child: BlockSurface(
            background: color,
            child: compact
                ? row
                : SizedBox(
                    width: _fullWidth,
                    child: Center(child: row),
                  ),
          ),
        );
      },
    );
  }
}

/// Glissé horizontal : un cran par geste, au-delà de [threshold].
///
/// Le détecteur de glissé horizontal gagne l'arène contre le `PageView` pour
/// tout glissé commencé sur le composant : la page ne change donc pas. Sans
/// vélo (`null`), le glissé est sans effet mais reste absorbé, pour ne pas
/// faire défiler la page sous le doigt.
class _Swipe extends StatefulWidget {
  const _Swipe({
    required this.threshold,
    required this.onLeft,
    required this.onRight,
    required this.child,
  });

  final double threshold;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final Widget child;

  @override
  State<_Swipe> createState() => _SwipeState();
}

class _SwipeState extends State<_Swipe> {
  double _travelled = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _travelled = 0,
    onHorizontalDragUpdate: (d) => _travelled += d.primaryDelta ?? 0,
    onHorizontalDragEnd: (_) {
      final travelled = _travelled;
      _travelled = 0;
      final action = travelled <= -widget.threshold
          ? widget.onLeft
          : travelled >= widget.threshold
          ? widget.onRight
          : null;
      if (action == null) return;
      HapticFeedback.mediumImpact();
      action();
    },
    onHorizontalDragCancel: () => _travelled = 0,
    child: widget.child,
  );
}
