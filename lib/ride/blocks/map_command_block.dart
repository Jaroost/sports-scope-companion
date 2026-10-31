import 'package:flutter/material.dart';

import '../../dashboard/ride_preset.dart';
import 'action_button.dart';

/// Un pas sur la carte (zoom, déplacement, recentrage), en case de bandeau ou
/// d'encoche. Compact seulement : une commande de carte se tape à l'aveugle,
/// elle n'a pas de plein format.
///
/// [onCommand] nul sur un profil sans carte, comme `onSleep` : un bouton sans
/// effet vaudrait moins que pas de bouton.
class MapCommandControl extends StatelessWidget {
  const MapCommandControl({
    super.key,
    required this.command,
    required this.onCommand,
    this.color,
    this.textColor,
  });

  final MapCommand command;
  final void Function(MapCommand command)? onCommand;
  final Color? color;
  final Color? textColor;

  static IconData iconOf(MapCommand command) => switch (command) {
        MapCommand.zoomIn => Icons.add,
        MapCommand.zoomOut => Icons.remove,
        MapCommand.panUp => Icons.keyboard_arrow_up,
        MapCommand.panDown => Icons.keyboard_arrow_down,
        MapCommand.panLeft => Icons.keyboard_arrow_left,
        MapCommand.panRight => Icons.keyboard_arrow_right,
        MapCommand.recenter => Icons.my_location,
      };

  @override
  Widget build(BuildContext context) => DashboardActionButton(
        icon: iconOf(command),
        label: command.label,
        compact: true,
        onPressed: onCommand == null ? null : () => onCommand!(command),
        color: color,
        textColor: textColor,
      );
}
