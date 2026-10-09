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
