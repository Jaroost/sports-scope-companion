import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../recording/ride_recorder.dart';

/// Un grand glissé horizontal sur une case d'entraînement saute le bloc en cours — mais
/// seulement s'il est optionnel (`optional` côté site : l'échauffement, par exemple).
///
/// Le détecteur n'est **posé que pendant un bloc optionnel** : le reste du temps la case
/// n'écoute rien, et un glissé qui la traverse change de page comme partout ailleurs.
/// Pendant un bloc optionnel, il prend le pas sur le `PageView` du tableau de bord pour un
/// glissé commencé sur la case — c'est voulu, et c'est pour ça que le seuil est large
/// ([_threshold]) : un petit geste maladroit au guidon ne doit rien sauter.
class WorkoutSkipSwipe extends StatefulWidget {
  const WorkoutSkipSwipe({super.key, required this.recorder, required this.child});

  final RideRecorder recorder;
  final Widget child;

  /// Distance horizontale cumulée (px logiques) au-delà de laquelle le glissé compte.
  static const _threshold = 120.0;

  @override
  State<WorkoutSkipSwipe> createState() => _WorkoutSkipSwipeState();
}

class _WorkoutSkipSwipeState extends State<WorkoutSkipSwipe> {
  double _travelled = 0;

  bool get _skippable {
    final program = widget.recorder.activeWorkout;
    final elapsed = widget.recorder.workoutElapsed;
    return program != null && elapsed != null && program.skippableSecondsAt(elapsed) != null;
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: widget.recorder, builder: (context, _) => _skippable ? _detector() : widget.child);

  Widget _detector() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _travelled = 0,
      onHorizontalDragUpdate: (details) => _travelled += details.primaryDelta ?? 0,
      onHorizontalDragEnd: (_) {
        final far = _travelled.abs() >= WorkoutSkipSwipe._threshold;
        _travelled = 0;
        if (far && widget.recorder.skipWorkoutBlock()) {
          HapticFeedback.mediumImpact();
        }
      },
      onHorizontalDragCancel: () => _travelled = 0,
      child: widget.child,
    );
  }
}
