import 'dart:async';

import 'package:flutter/material.dart';

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
        fontSize: widget.mode == StopwatchMode.compact ? 34 : 56,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final toggle = controller.isRunning
        ? _button(Icons.pause, 'Arrêter le chronomètre', controller.toggle)
        : _button(Icons.play_arrow, 'Démarrer le chronomètre', controller.toggle);
    final reset = _button(
      Icons.restart_alt,
      'Remettre le chronomètre à zéro',
      controller.isZero ? null : controller.reset,
    );

    final title = widget.label.isEmpty
        ? null
        : Text(
            widget.label,
            style: TextStyle(color: widget.textColor ?? Colors.white70, fontSize: 15),
          );

    return BlockSurface(
      background: widget.color,
      child: SizedBox(
        width: StopwatchCard._naturalWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[title, const SizedBox(height: 4)],
            time,
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [toggle, const SizedBox(width: 12), reset],
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback? onPressed) {
    final compact = widget.mode == StopwatchMode.compact;
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        iconSize: compact ? 22 : 30,
        // Gros : le doigt vise mal sur une route bosselée.
        constraints: BoxConstraints.tightFor(
          width: compact ? 44 : 64,
          height: compact ? 44 : 56,
        ),
        onPressed: onPressed,
        icon: Icon(icon),
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
    final background = flashOn ? TimerCard._flashColor : widget.color;
    final fg = flashOn ? Colors.white : (widget.textColor ?? Colors.white);

    return BlockSurface(
      background: background,
      child: SizedBox(
        width: StopwatchCard._naturalWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label.isNotEmpty) ...[
              Text(widget.label, style: TextStyle(color: fg, fontSize: 15)),
              const SizedBox(height: 4),
            ],
            Text(
              formatDuration(c.remaining),
              style: TextStyle(
                color: fg,
                fontSize: compact ? 34 : 56,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Fini, ce bouton acquitte (arrête le son et le clignotement).
                _button(
                  compact,
                  c.isFinished
                      ? Icons.stop
                      : (c.isRunning ? Icons.pause : Icons.play_arrow),
                  c.isFinished
                      ? 'Arrêter l\'alerte'
                      : (c.isRunning ? 'Arrêter le minuteur' : 'Démarrer le minuteur'),
                  c.toggle,
                ),
                const SizedBox(width: 12),
                _button(
                  compact,
                  Icons.restart_alt,
                  'Remettre le minuteur à zéro',
                  c.isUntouched ? null : c.reset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(bool compact, IconData icon, String tooltip, VoidCallback? onPressed) =>
      Tooltip(
        message: tooltip,
        child: IconButton.filledTonal(
          iconSize: compact ? 22 : 30,
          constraints: BoxConstraints.tightFor(
            width: compact ? 44 : 64,
            height: compact ? 44 : 56,
          ),
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      );
}
