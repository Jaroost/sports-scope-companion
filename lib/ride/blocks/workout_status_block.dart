import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/companion_icons.dart';
import '../../dashboard/dashboard_block.dart' show WorkoutStatusMode;
import '../../recording/ride_recorder.dart';
import '../../training_program/training_program.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';
import 'block_card.dart';
import '../widgets/workout_skip_swipe.dart';

/// Le tronçon d'entraînement en cours et le temps restant avant le prochain
/// jalon, dans une seule carte — [WorkoutSegmentCard] et
/// [WorkoutRemainingCard] fondues, pour la page qui n'a la place que d'une
/// case mais veut les deux informations plutôt que choisir entre elles.
///
/// Deux mises en page ([WorkoutStatusMode]) : [WorkoutStatusMode.full] sur
/// deux lignes (le tronçon, puis le temps restant, chacun son titre), ou
/// [WorkoutStatusMode.line] fondues sur une seule — icône, nom, temps
/// restant, même contenu que [WorkoutBandTile] au langage visuel d'une
/// carte de page.
///
/// Même source ([RideRecorder.activeWorkout]/[RideRecorder.workoutElapsed],
/// `TrainingProgram.milestoneAt`/`remainingAt`) et même précédence de
/// couleur (réglage du bloc, puis [WorkoutMilestone.color]/[textColor], puis
/// repli) que les deux cartes d'origine — elles restent posables
/// séparément, celle-ci n'est qu'une troisième façon de lire le même état.
class WorkoutStatusCard extends StatelessWidget {
  const WorkoutStatusCard({
    super.key,
    required this.recorder,
    required this.mode,
    this.upcoming = false,
    this.color,
    this.textColor,
  });

  final RideRecorder recorder;
  final WorkoutStatusMode mode;

  /// Montre le tronçon qui suivra celui en cours et sa durée
  /// ([TrainingProgram.nextMilestoneAt]/[TrainingProgram.nextSegmentDurationAt])
  /// plutôt que le tronçon en cours et son temps restant — même sens que
  /// [WorkoutSegmentCard.upcoming]/[WorkoutRemainingCard.upcoming], appliqué
  /// aux deux informations à la fois.
  final bool upcoming;
  final Color? color;
  final Color? textColor;

  static const _lineWidth = 260.0;
  static const _figureSize = 24.0;
  static const _finished = 'Terminé';

  @override
  Widget build(BuildContext context) => WorkoutSkipSwipe(
    recorder: recorder,
    child: ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final program = recorder.activeWorkout;
        final elapsed = recorder.workoutElapsed;
        final milestone = program != null && elapsed != null
            ? (upcoming ? program.nextMilestoneAt(elapsed) : program.milestoneAt(elapsed))
            : null;
        final remaining = program != null && elapsed != null
            ? (upcoming ? program.nextSegmentDurationAt(elapsed) : program.remainingAt(elapsed))
            : null;

        final background = color ?? milestone?.color;
        final ink = textColor ?? milestone?.textColor ?? (background == null ? Colors.white : foregroundOf(background));
        const metrics = BlockMetrics.natural;

        final name = milestone?.segmentName;
        final segmentLabel = (name == null || name.isEmpty) ? '—' : name;
        // `upcoming` n'a pas de « Terminé » : ce tronçon n'a pas commencé,
        // rien à annoncer de fini — juste un tiret quand sa durée n'est pas
        // connue (dernier de la timeline, programme absent).
        final String remainingLabel;
        if (program == null) {
          remainingLabel = '—';
        } else if (remaining == null) {
          remainingLabel = upcoming ? '—' : _finished;
        } else {
          remainingLabel = formatDuration(remaining);
        }
        final icon = workoutMilestoneIconFor(milestone?.icon);

        // Tronçon en cours optionnel : un grand glissé le saute (`WorkoutSkipSwipe`), on le dit.
        final skippable = !upcoming && milestone?.optional == true;
        final line = mode == WorkoutStatusMode.line;
        return BlockSurface(
          background: background,
          // Mode complet : le contenu remplit la case, le plus large et le plus haut possible.
          grow: !line,
          child: line
              ? SizedBox(width: _lineWidth, child: _line(icon, segmentLabel, remainingLabel, ink, metrics, skippable: skippable))
              : _full(icon, segmentLabel, remainingLabel, ink, metrics, skippable: skippable),
        );
      },
    ),
  );

  /// [WorkoutStatusMode.full] : le tronçon, puis le temps restant, chacun sa
  /// ligne — mêmes rangées que [WorkoutSegmentCard]/[WorkoutRemainingCard].
  ///
  /// Les deux lignes sont **centrées**, à leur largeur naturelle : le nom du tronçon n'est
  /// jamais coupé, c'est la mise à l'échelle de la carte (qui ici agrandit aussi, `grow`) qui
  /// le fait tenir — aussi large et aussi haut que la case le permet.
  Widget _full(
    FaIconData icon,
    String segment,
    String remaining,
    Color ink,
    BlockMetrics metrics, {
    required bool skippable,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      _centeredRow(icon, segment, ink, metrics),
      SizedBox(height: metrics.gap * 0.6),
      _centeredRow(FontAwesomeIcons.stopwatch, remaining, ink, metrics, skippable: skippable),
    ],
  );

  Widget _centeredRow(
    FaIconData icon,
    String label,
    Color ink,
    BlockMetrics metrics, {
    bool skippable = false,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      FaIcon(icon, size: _figureSize * 0.8, color: ink.withValues(alpha: 0.85)),
      SizedBox(width: metrics.gap * 0.6),
      Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(color: ink, fontSize: _figureSize, fontWeight: FontWeight.w500),
      ),
      if (skippable) ..._skipHint(ink, metrics),
    ],
  );

  /// L'indication « glisser pour sauter », en bout de ligne : l'icône d'avance rapide.
  List<Widget> _skipHint(Color ink, BlockMetrics metrics) => [
    SizedBox(width: metrics.gap * 0.6),
    FaIcon(FontAwesomeIcons.forward, size: _figureSize * 0.7, color: ink.withValues(alpha: 0.7)),
  ];

  /// [WorkoutStatusMode.line] : icône, nom du tronçon et temps restant sur
  /// une seule ligne — le nom cède la place en premier (`Expanded` +
  /// ellipse), le temps ne tronque jamais.
  Widget _line(
    FaIconData icon,
    String segment,
    String remaining,
    Color ink,
    BlockMetrics metrics, {
    required bool skippable,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      FaIcon(icon, size: metrics.iconSize, color: ink.withValues(alpha: 0.85)),
      SizedBox(width: metrics.gap * 0.6),
      Expanded(
        child: Text(
          segment,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: ink, fontSize: _figureSize, fontWeight: FontWeight.w500),
        ),
      ),
      SizedBox(width: metrics.gap),
      Text(
        remaining,
        maxLines: 1,
        style: TextStyle(color: ink, fontSize: _figureSize, fontWeight: FontWeight.w500),
      ),
      if (skippable) ..._skipHint(ink, metrics),
    ],
  );
}
