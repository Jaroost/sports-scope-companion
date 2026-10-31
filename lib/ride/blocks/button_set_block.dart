import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../dashboard/companion_icons.dart';
import '../../dashboard/ride_preset.dart';
import 'action_button.dart';

/// Passe au set de commandes suivant (`next_button_set`), en case de bandeau ou
/// d'encoche. Compact seulement : comme une commande de carte, ça se tape à
/// l'aveugle.
///
/// Le bouton prend l'**icône et la couleur du set en cours** ([current]) : on
/// lit sur la case dans quel jeu de touches on se trouve. Une couleur de fond
/// réglée sur la case ([color]) l'emporte sur celle du set.
///
/// [onNext] nul avec un seul set : un bouton sans effet vaudrait moins que pas
/// de bouton.
class ButtonSetControl extends StatelessWidget {
  const ButtonSetControl({
    super.key,
    required this.current,
    required this.onNext,
    this.color,
    this.textColor,
  });

  final ValueListenable<ButtonSet> current;
  final VoidCallback? onNext;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ButtonSet>(
        valueListenable: current,
        builder: (context, set, _) => DashboardActionButton(
          icon: companionIconFor(set.icon)?.data ?? Icons.swap_horiz,
          label: set.name.isEmpty ? 'Set de commandes suivant' : set.name,
          compact: true,
          onPressed: onNext,
          color: color ?? set.color,
          textColor: textColor,
        ),
      );
}
