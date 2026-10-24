import 'dart:async';

import 'package:flutter/cupertino.dart'
    show
        CupertinoTheme,
        CupertinoThemeData,
        CupertinoTextThemeData,
        CupertinoTimerPicker,
        CupertinoTimerPickerMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dashboard/dashboard_block.dart';
import '../../ui/formats.dart';
import '../stopwatch_registry.dart';
import 'block_card.dart';

/// Un chronomètre posé sur une page — voir `StopwatchBlock`
/// (`dashboard_block.dart`).
///
/// Deux boutons : démarrer/arrêter (un seul, qui change de glyphe) et remise
/// à zéro. Le chrono lui-même vit dans [StopwatchRegistry], pas ici : ce
/// widget n'est que sa vitre, et ne tourne (tic de 250 ms) que tant que le
/// chrono court.
class StopwatchCard extends StatefulWidget {
  const StopwatchCard({
    super.key,
    required this.controller,
    required this.label,
    this.mode = StopwatchMode.full,
    this.color,
    this.textColor,
  });

  final StopwatchController controller;

  /// Le titre réglé dans l'éditeur ; vide, la carte n'en porte pas.
  final String label;
  final StopwatchMode mode;
  final Color? color;
  final Color? textColor;

  static const _naturalWidth = 200.0;

  /// Fond tant que le chrono court (ou que le minuteur décompte), à la place
  /// de la couleur réglée : on voit d'un coup d'œil qu'il tourne.
  static const _runningColor = Color(0xFF2E7D32);

  @override
  State<StopwatchCard> createState() => _StopwatchCardState();
}

class _StopwatchCardState extends State<StopwatchCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _syncTick();
  }

  @override
  void didUpdateWidget(StopwatchCard old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _syncTick();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _tick?.cancel();
    super.dispose();
  }

  void _onChanged() {
    _syncTick();
    if (mounted) setState(() {});
  }

  void _syncTick() {
    if (widget.controller.isRunning) {
      _tick ??= Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => mounted ? setState(() {}) : null,
      );
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final fg = widget.textColor ?? Colors.white;
    final time = Text(
      formatDuration(controller.elapsed),
      style: TextStyle(
        color: fg,
        fontSize: widget.mode == StopwatchMode.compact ? 40 : 68,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final header = _CornerControls(
      compact: widget.mode == StopwatchMode.compact,
      label: widget.label,
      labelColor: widget.textColor ?? Colors.white70,
      resetIcon: Icons.restart_alt,
      resetTooltip: 'Remettre le chronomètre à zéro',
      onReset: controller.isZero ? null : controller.reset,
      toggleIcon: controller.isRunning ? Icons.pause : Icons.play_arrow,
      toggleTooltip: controller.isRunning
          ? 'Arrêter le chronomètre'
          : 'Démarrer le chronomètre',
      onToggle: controller.toggle,
    );

    return _SwipeControls(
      onStartStop: controller.toggle,
      onReset: controller.isZero ? null : controller.reset,
      child: BlockSurface(
        background: controller.isRunning
            ? StopwatchCard._runningColor
            : widget.color,
        child: SizedBox(
          width: StopwatchCard._naturalWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              FittedBox(fit: BoxFit.scaleDown, child: time),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un minuteur posé sur une page — voir `TimerBlock` (`dashboard_block.dart`).
///
/// Même vitre que [StopwatchCard] sur un [TimerController] : le compte à
/// rebours, l'échéance et le son vivent dans le contrôleur. Ici seulement le
/// rafraîchissement de l'affichage (tic de 250 ms tant qu'il court) et le
/// clignotement du fond une fois fini (500 ms, rouge / fond normal).
class TimerCard extends StatefulWidget {
  const TimerCard({
    super.key,
    required this.controller,
    required this.label,
    this.mode = StopwatchMode.full,
    this.color,
    this.textColor,
  });

  final TimerController controller;
  final String label;
  final StopwatchMode mode;
  final Color? color;
  final Color? textColor;

  static const _flashColor = Color(0xFFC62828);

  @override
  State<TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends State<TimerCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _syncTick();
  }

  @override
  void didUpdateWidget(TimerCard old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _syncTick();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _tick?.cancel();
    super.dispose();
  }

  void _onChanged() {
    _syncTick();
    if (mounted) setState(() {});
  }

  // Court tant qu'il décompte ; clignote (tic de 500 ms) une fois fini.
  void _syncTick() {
    final c = widget.controller;
    _tick?.cancel();
    _tick = null;
    if (c.isRunning || c.isFinished) {
      _tick = Timer.periodic(
        Duration(milliseconds: c.isFinished ? 500 : 250),
        (_) => mounted ? setState(() {}) : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final compact = widget.mode == StopwatchMode.compact;
    // Clignote en alternant sur la phase de l'horloge : deux cartes de même
    // minuteur restent synchrones sans état de plus.
    final flashOn =
        c.isFinished && DateTime.now().millisecondsSinceEpoch ~/ 500 % 2 == 0;
    final background = flashOn
        ? TimerCard._flashColor
        : (c.isRunning ? StopwatchCard._runningColor : widget.color);
    final fg = flashOn ? Colors.white : (widget.textColor ?? Colors.white);

    return _SwipeControls(
      onStartStop: c.toggle,
      onReset: c.isUntouched ? null : c.reset,
      child: BlockSurface(
        background: background,
        child: SizedBox(
          width: StopwatchCard._naturalWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CornerControls(
                compact: compact,
                label: widget.label,
                labelColor: fg,
                resetIcon: Icons.restart_alt,
                resetTooltip: 'Remettre le minuteur à zéro',
                onReset: c.isUntouched ? null : c.reset,
                // Fini, ce bouton acquitte (arrête le son et le clignotement).
                toggleIcon: c.isFinished
                    ? Icons.stop
                    : (c.isRunning ? Icons.pause : Icons.play_arrow),
                toggleTooltip: c.isFinished
                    ? 'Arrêter l\'alerte'
                    : (c.isRunning
                          ? 'Arrêter le minuteur'
                          : 'Démarrer le minuteur'),
                onToggle: c.toggle,
              ),
              // Touchable seulement avant le départ : le temps sert alors de
              // réglage de la durée.
              InkWell(
                onTap: c.isUntouched ? () => _editDuration(context) : null,
                borderRadius: BorderRadius.circular(8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDuration(c.remaining),
                        style: TextStyle(
                          color: fg,
                          fontSize: compact ? 40 : 68,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (c.isUntouched) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit,
                          size: compact ? 14 : 18,
                          color: fg.withValues(alpha: 0.54),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Minutes + secondes, à la molette. Annuler laisse la durée telle quelle ;
  /// zéro est refusé par le contrôleur (un minuteur de 0 s n'a pas de sens).
  Future<void> _editDuration(BuildContext context) async {
    var picked = widget.controller.remaining;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Fond sombre explicite, celui des cartes : la dialogue héritait du
        // blanc du thème, où les molettes blanches ne se lisaient plus.
        backgroundColor: BlockCard.background,
        title: const Text(
          'Durée du minuteur',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          height: 180,
          width: 280,
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.dark,
              textTheme: CupertinoTextThemeData(
                pickerTextStyle: TextStyle(color: Colors.white, fontSize: 22),
                dateTimePickerTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                ),
              ),
            ),
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.ms,
              initialTimerDuration: picked,
              onTimerDurationChanged: (d) => picked = d,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Annuler',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok == true) widget.controller.setDuration(picked);
  }
}

/// Glissé horizontal sur un chronomètre ou un minuteur : vers la gauche il
/// démarre / arrête, vers la droite il remet à zéro.
///
/// Le détecteur de glissé horizontal gagne l'arène des gestes contre le
/// `PageView` pour tout glissé commencé sur la carte : la page ne change donc
/// pas. Seuil modeste ([_threshold]) — le geste est voulu, mais on le fait au
/// guidon.
class _SwipeControls extends StatefulWidget {
  const _SwipeControls({
    required this.onStartStop,
    required this.onReset,
    required this.child,
  });

  final VoidCallback onStartStop;

  /// `null` : rien à remettre à zéro, le glissé vers la droite est sans effet
  /// (la page ne change pas pour autant).
  final VoidCallback? onReset;
  final Widget child;

  static const _threshold = 50.0;

  @override
  State<_SwipeControls> createState() => _SwipeControlsState();
}

class _SwipeControlsState extends State<_SwipeControls> {
  double _travelled = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _travelled = 0,
    onHorizontalDragUpdate: (d) => _travelled += d.primaryDelta ?? 0,
    onHorizontalDragEnd: (_) {
      final travelled = _travelled;
      _travelled = 0;
      if (travelled <= -_SwipeControls._threshold) {
        HapticFeedback.mediumImpact();
        widget.onStartStop();
      } else if (travelled >= _SwipeControls._threshold &&
          widget.onReset != null) {
        HapticFeedback.mediumImpact();
        widget.onReset!();
      }
    },
    onHorizontalDragCancel: () => _travelled = 0,
    child: widget.child,
  );
}

/// Rangée du haut d'un chronomètre ou d'un minuteur : démarrer / arrêter en haut à
/// gauche, remise à zéro en haut à droite, le titre entre les deux.
///
/// Petits, pour laisser la place au temps ; la flèche rappelle le glissé qui
/// fait la même chose ([_SwipeControls]) — vers la droite pour remettre à
/// zéro, vers la gauche pour démarrer / arrêter.
class _CornerControls extends StatelessWidget {
  const _CornerControls({
    required this.compact,
    required this.label,
    required this.labelColor,
    required this.resetIcon,
    required this.resetTooltip,
    required this.onReset,
    required this.toggleIcon,
    required this.toggleTooltip,
    required this.onToggle,
  });

  final bool compact;
  final String label;
  final Color labelColor;
  final IconData resetIcon;
  final String resetTooltip;
  final VoidCallback? onReset;
  final IconData toggleIcon;
  final String toggleTooltip;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _small(toggleTooltip, onToggle, [
        Icon(Icons.arrow_back, size: compact ? 12 : 14),
        Icon(toggleIcon, size: compact ? 16 : 18),
      ]),
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: labelColor, fontSize: 15),
        ),
      ),
      _small(resetTooltip, onReset, [
        Icon(resetIcon, size: compact ? 16 : 18),
        Icon(Icons.arrow_forward, size: compact ? 12 : 14),
      ]),
    ],
  );

  Widget _small(String tooltip, VoidCallback? onPressed, List<Widget> icons) =>
      Tooltip(
        message: tooltip,
        child: FilledButton.tonal(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size(compact ? 40 : 48, compact ? 28 : 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: icons),
        ),
      );
}
