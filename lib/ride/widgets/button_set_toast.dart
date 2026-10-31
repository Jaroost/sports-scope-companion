import 'package:flutter/material.dart';

import '../../dashboard/companion_icons.dart';
import '../../dashboard/ride_preset.dart';

/// Le toast qui annonce le set de commandes sélectionné — voir
/// `RideShellPage._nextButtonSet`, qui l'affiche quelques secondes puis
/// l'efface.
///
/// Même forme que [LapStartedToast] (un bandeau, pas une boîte à fermer, sans
/// prise sur les gestes), mais **en haut** : le bas porte déjà le toast de tour
/// et le bandeau, et le set se change aussi bien depuis une touche que depuis
/// une case. Le filet de gauche et l'icône reprennent ceux du set.
class ButtonSetToast extends StatelessWidget {
  const ButtonSetToast({super.key, required this.set});

  final ButtonSet set;

  @override
  Widget build(BuildContext context) {
    final accent = set.color ?? Colors.white;
    return IgnorePointer(
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 72),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(companionIconFor(set.icon)?.data ?? Icons.swap_horiz, color: accent, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Commandes : ${set.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
