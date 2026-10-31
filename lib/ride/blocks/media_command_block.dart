import 'package:flutter/material.dart';

import '../../dashboard/ride_preset.dart';
import '../../phone/media_control.dart';
import 'action_button.dart';

/// Une commande du lecteur de musique, en case de bandeau ou d'encoche.
/// Compact seulement, comme [MapCommandControl] : se tape à l'aveugle.
class MediaCommandControl extends StatelessWidget {
  const MediaCommandControl({super.key, required this.command, this.color, this.textColor});

  final MediaCommand command;
  final Color? color;
  final Color? textColor;

  static IconData iconOf(MediaCommand command) => switch (command) {
        MediaCommand.volumeUp => Icons.volume_up,
        MediaCommand.volumeDown => Icons.volume_down,
        MediaCommand.next => Icons.skip_next,
        MediaCommand.previous => Icons.skip_previous,
        MediaCommand.playPause => Icons.play_arrow,
      };

  @override
  Widget build(BuildContext context) => DashboardActionButton(
        icon: iconOf(command),
        label: command.label,
        compact: true,
        onPressed: () => MediaControl.run(command),
        color: color,
        textColor: textColor,
      );
}
