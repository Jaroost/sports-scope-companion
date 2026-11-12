import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../phone/torch_control.dart';
import 'action_button.dart';

/// Bascule la lampe torche, en case de bandeau ou d'encoche. Compact par défaut (bandeau/encoche),
/// pleine largeur pour un bloc de page en mode `full`. L'icône dit l'état.
class TorchCommandControl extends StatelessWidget {
  const TorchCommandControl({super.key, this.mode = TorchMode.compact, this.color, this.textColor});

  final TorchMode mode;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: TorchControl.isOn,
        builder: (context, on, _) => DashboardActionButton(
          icon: on ? Icons.flashlight_on : Icons.flashlight_off,
          label: 'Lampe',
          compact: mode == TorchMode.compact,
          onPressed: TorchControl.toggle,
          color: color,
          textColor: textColor,
        ),
      );
}
