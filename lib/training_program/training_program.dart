import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

/// Les huit sons qu'un jalon peut jouer — catalogue fermé, miroir exact de
/// `TrainingProgram::SOUNDS` côté Rails. La plupart sont ceux déjà embarqués
/// pour le radar, les cols et les klaxons ; `end2`/`end3` n'existent que pour
/// un programme d'entraînement (variantes de fin de tronçon), mais suivent le
/// même catalogue fermé plutôt qu'une liste à part.
enum WorkoutSound {
  start('start'),
  end('end'),
  end2('end2'),
  end3('end3'),
  bell('bell'),
  horn('horn'),
  horn2('horn2'),
  booster('booster');

  const WorkoutSound(this.key);

  final String key;

  String get asset => 'sounds/$key.wav';

  static WorkoutSound? parse(Object? raw) {
    if (raw is! String) return null;
    for (final sound in WorkoutSound.values) {
      if (sound.key == raw) return sound;
    }
    return null;
  }
}

/// Les dix icônes qu'un jalon peut porter — catalogue fermé, miroir exact de
/// `TrainingProgram::ICONS` côté Rails et de `MILESTONE_ICONS`
/// (`trainingProgramStore.ts`). Purement descriptif ici : le dessin réel
/// (quelle icône FontAwesome pour quelle clé) vit dans `companion_icons.dart`,
/// pas dans ce fichier qui n'importe volontairement aucun paquet d'UI.
enum WorkoutMilestoneIcon {
  warmup('warmup'),
  sprint('sprint'),
  effort('effort'),
  recovery('recovery'),
  climb('climb'),
  cooldown('cooldown'),
  interval('interval'),
  hydration('hydration'),
  alert('alert'),
  finish('finish');

  const WorkoutMilestoneIcon(this.key);

  final String key;

  static WorkoutMilestoneIcon? parse(Object? raw) {
    if (raw is! String) return null;
    for (final icon in WorkoutMilestoneIcon.values) {
      if (icon.key == raw) return icon;
    }
    return null;
  }
}

/// Le moment où joue un son, relatif à la frontière qu'il accompagne (le
/// début ou la fin d'un bloc) — catalogue fermé, miroir de
/// `TrainingProgram::CUE_TIMINGS` (`training_program.rb`).
enum WorkoutCueTiming {
  /// Décalé en avance pour se **terminer** pile sur la frontière
  /// ([WorkoutCuePolicy]).
  before('before'),

  /// Démarre pile sur la frontière, sans anticipation.
  at('at');

  const WorkoutCueTiming(this.key);

  final String key;

  /// [fallback] sur toute valeur absente ou inconnue. Il n'y a pas de défaut
  /// unique : un son de début joue dans le bloc ([at]), un son de fin aussi
  /// ([before], il se termine avec le bloc) — `DEFAULT_START_TIMING` /
  /// `DEFAULT_END_TIMING` côté site. L'ancien format, lui, n'avait que
  /// [before] pour défaut.
  static WorkoutCueTiming parse(Object? raw, {required WorkoutCueTiming fallback}) {
    if (raw is String) {
      for (final timing in WorkoutCueTiming.values) {
        if (timing.key == raw) return timing;
      }
    }
    return fallback;
  }
}

/// Un son à jouer sur une frontière du programme : [boundarySeconds] depuis
/// l'activation — le début d'un bloc, ou sa fin (qui est aussi le début du
/// suivant). Le programme en porte la liste à part ([TrainingProgram.cues]) :
/// un bloc peut avoir un son à chaque bout, avec chacun son [timing].
@immutable
class WorkoutCue {
  const WorkoutCue({
    required this.boundarySeconds,
    required this.sound,
    required this.timing,
  });

  final int boundarySeconds;
  final WorkoutSound sound;
  final WorkoutCueTiming timing;
}

/// Un jalon de la timeline : à [offsetSeconds] de l'activation du programme,
/// il ferme le tronçon en cours et en ouvre un nouveau nommé [segmentName].
/// C'est le début d'un bloc du site ; le dernier jalon, sans nom ni cibles,
/// n'est que la fin du dernier bloc. Les sons ne sont pas portés ici mais
/// par [TrainingProgram.cues].
@immutable
class WorkoutMilestone {
  const WorkoutMilestone({
    required this.offsetSeconds,
    required this.segmentName,
    required this.description,
    required this.icon,
    required this.color,
    required this.textColor,
    this.optional = false,
    required this.targetPower,
    required this.minPower,
    required this.maxPower,
    required this.targetHeartRate,
    required this.minHeartRate,
    required this.maxHeartRate,
    required this.targetCadence,
    required this.minCadence,
    required this.maxCadence,
    required this.targetSpeedKmh,
    required this.minSpeedKmh,
    required this.maxSpeedKmh,
  });

  final int offsetSeconds;
  final String segmentName;

  /// Le texte que l'appli lit à voix haute à l'ouverture du tronçon
  /// (`WorkoutSpeaker`) ; vide quand le bloc n'en porte pas — rien à dire.
  final String description;

  /// L'icône du tronçon qu'ouvre ce jalon — voir `workoutMilestoneIconFor`
  /// (`companion_icons.dart`) pour le dessin réel.
  final WorkoutMilestoneIcon? icon;

  /// Fond/texte du tronçon, réglés dans l'éditeur — mêmes `#rrggbb` que
  /// `DashboardBlock.color`/`textColor`, mais propres au jalon : c'est ce que
  /// lisent `WorkoutSegmentCard`/`WorkoutRemainingCard` en repli quand le bloc
  /// lui-même ne fixe pas sa propre couleur.
  final Color? color;
  final Color? textColor;

  /// Le bloc peut être sauté d'un grand glissé (l'échauffement, par exemple) —
  /// `optional` côté site. Absent vaut `false` : un bloc d'un document plus ancien
  /// que l'appli reste obligatoire, jamais sauté par mégarde.
  final bool optional;

  /// Cible + bornes de ce step pour les quatre mesures en direct, réglées
  /// dans l'éditeur du site (`TrainingProgram::TARGET_FIELDS`, même unités :
  /// W, bpm, tr/min, km/h). `target*` n'est pas encore affiché ici — seuls
  /// `min*`/`max*` pilotent la couleur de fond des composants de mesure, voir
  /// `workoutTargetColorFor` (`workout_target_color.dart`). Une borne absente
  /// ne referme pas ce côté-là (ni min ni max n'implique l'autre).
  final double? targetPower;
  final double? minPower;
  final double? maxPower;
  final double? targetHeartRate;
  final double? minHeartRate;
  final double? maxHeartRate;
  final double? targetCadence;
  final double? minCadence;
  final double? maxCadence;
  final double? targetSpeedKmh;
  final double? minSpeedKmh;
  final double? maxSpeedKmh;

  /// Le jalon qui ouvre le bloc [raw] (ou, dans l'ancien format, le jalon
  /// [raw] lui-même), à [offsetSeconds]. Les sons ne sont pas lus ici.
  static WorkoutMilestone fromMap(Map raw, int offsetSeconds) {
    return WorkoutMilestone(
      offsetSeconds: offsetSeconds,
      segmentName: raw['segment_name'] is String ? raw['segment_name'] as String : '',
      description: raw['description'] is String ? (raw['description'] as String).trim() : '',
      icon: WorkoutMilestoneIcon.parse(raw['icon']),
      color: _colorOf(raw['color']),
      textColor: _colorOf(raw['text_color']),
      optional: raw['optional'] == true,
      targetPower: _numOf(raw['target_power']),
      minPower: _numOf(raw['min_power']),
      maxPower: _numOf(raw['max_power']),
      targetHeartRate: _numOf(raw['target_heart_rate']),
      minHeartRate: _numOf(raw['min_heart_rate']),
      maxHeartRate: _numOf(raw['max_heart_rate']),
      targetCadence: _numOf(raw['target_cadence']),
      minCadence: _numOf(raw['min_cadence']),
      maxCadence: _numOf(raw['max_cadence']),
      targetSpeedKmh: _numOf(raw['target_speed_kmh']),
      minSpeedKmh: _numOf(raw['min_speed_kmh']),
      maxSpeedKmh: _numOf(raw['max_speed_kmh']),
    );
  }

  /// Le jalon de fin de programme : rien à nommer ni à viser, il ne fait que
  /// clore le dernier bloc (voir [TrainingProgram.milestones]).
  static WorkoutMilestone closing(int offsetSeconds) => WorkoutMilestone(
        offsetSeconds: offsetSeconds,
        segmentName: '',
        description: '',
        icon: null,
        color: null,
        textColor: null,
        targetPower: null,
        minPower: null,
        maxPower: null,
        targetHeartRate: null,
        minHeartRate: null,
        maxHeartRate: null,
        targetCadence: null,
        minCadence: null,
        maxCadence: null,
        targetSpeedKmh: null,
        minSpeedKmh: null,
        maxSpeedKmh: null,
      );

  static double? _numOf(Object? raw) => raw is num ? raw.toDouble() : null;

  /// `#rrggbb` uniquement — même format que `sanitize_hex_color` côté site,
  /// mais l'appli ne lui fait pas confiance pour autant (même garde que
  /// `DashboardBlock._colorOf`, `dashboard_block.dart`).
  static Color? _colorOf(Object? raw) {
    if (raw is! String) return null;
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(raw);
    if (match == null) return null;
    return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }
}

/// Un programme d'entraînement du site, réduit à ce qu'il faut pour le
/// dérouler pendant une sortie.
///
/// Même principe que `RouteSummary` : le [shareToken] est la seule clé dont
/// l'appli a besoin, la navigation/le déroulement sont adressés par lui côté
/// Rails plutôt que par l'identifiant interne.
@immutable
class TrainingProgram {
  const TrainingProgram({
    required this.id,
    required this.name,
    required this.shareToken,
    required this.milestones,
    this.cues = const [],
  });

  final int id;
  final String name;
  final String shareToken;

  /// Le début de chaque bloc, puis un jalon de clôture à la fin du dernier.
  /// Triés par [WorkoutMilestone.offsetSeconds] strictement croissant, premier
  /// élément toujours à 0 — revérifié ici au parse plutôt que supposé.
  final List<WorkoutMilestone> milestones;

  /// Les sons du programme, un par son réglé sur le début ou la fin d'un
  /// bloc. Leur ordre n'est pas garanti : [WorkoutCuePolicy] les trie par
  /// instant de départ, qui dépend de la durée du son.
  final List<WorkoutCue> cues;

  /// Le tronçon en cours à [elapsed] — le dernier jalon dont l'offset est déjà
  /// atteint. Jamais `null` en pratique (le premier jalon est toujours à 0,
  /// garanti par [parse]) : signature nullable seulement pour un [elapsed]
  /// négatif, qu'aucun appelant ne produit.
  ///
  /// Pure et sans curseur, contrairement à `WorkoutPolicy.read` (qui ne rend
  /// un jalon franchi qu'une fois, au tic où il l'est) — c'est ce qu'il faut
  /// pour une case de tableau de bord, qui redemande le tronçon courant à
  /// chaque rebuild plutôt qu'une seule fois au passage.
  WorkoutMilestone? milestoneAt(Duration elapsed) {
    WorkoutMilestone? current;
    for (final milestone in milestones) {
      if (milestone.offsetSeconds > elapsed.inSeconds) break;
      current = milestone;
    }
    return current;
  }

  /// Combien de secondes il reste du tronçon en cours **s'il est optionnel**, `null`
  /// sinon (obligatoire, ou programme terminé). C'est de combien avancer l'horloge du
  /// programme pour sauter ce bloc ([RideRecorder.skipWorkoutBlock]).
  int? skippableSecondsAt(Duration elapsed) {
    final current = milestoneAt(elapsed);
    final remaining = remainingAt(elapsed);
    if (current == null || remaining == null || !current.optional) return null;
    return remaining.inSeconds;
  }

  /// Le temps avant le prochain jalon, `null` une fois le dernier dépassé
  /// (programme terminé) — même caractère pur que [milestoneAt].
  Duration? remainingAt(Duration elapsed) {
    for (final milestone in milestones) {
      if (milestone.offsetSeconds > elapsed.inSeconds) {
        return Duration(seconds: milestone.offsetSeconds - elapsed.inSeconds);
      }
    }
    return null;
  }

  /// Le jalon qui suit [elapsed], `null` une fois le dernier dépassé — sert à
  /// annoncer le tronçon suivant en aperçu (`WorkoutBadge.upcoming`) avant
  /// qu'il ne devienne le tronçon en cours. Même caractère pur que
  /// [milestoneAt]/[remainingAt].
  WorkoutMilestone? nextMilestoneAt(Duration elapsed) {
    for (final milestone in milestones) {
      if (milestone.offsetSeconds > elapsed.inSeconds) return milestone;
    }
    return null;
  }

  /// La durée du tronçon qui suivra celui en cours — l'intervalle entre le
  /// jalon de [nextMilestoneAt] et celui d'après, pas un compte à rebours
  /// vers son départ (ça, c'est [remainingAt]). `null` si ce tronçon n'a pas
  /// encore commencé (dernier jalon dépassé) ou s'il n'a pas de fin connue
  /// (c'est le dernier de la timeline, ouvert jusqu'à la fin du programme) —
  /// dans les deux cas rien à annoncer plutôt qu'une durée devinée. Sert à
  /// [WorkoutRemainingCard]/[WorkoutStatusCard] en aperçu (`upcoming`).
  Duration? nextSegmentDurationAt(Duration elapsed) {
    for (var i = 0; i < milestones.length; i++) {
      if (milestones[i].offsetSeconds > elapsed.inSeconds) {
        if (i + 1 >= milestones.length) return null;
        return Duration(seconds: milestones[i + 1].offsetSeconds - milestones[i].offsetSeconds);
      }
    }
    return null;
  }

  /// Décode `{ training_program: {...} }` ou l'objet programme directement.
  /// Défensif comme `RidePreset.parse` : jamais d'exception, `null` si le
  /// document est inexploitable — un programme à moitié compris ne doit
  /// jamais se dérouler à moitié.
  ///
  /// Lit `blocks` (durée + sons de début/fin par bloc) ; à défaut, l'ancien
  /// format `milestones` (instants cumulés, un son par jalon), qu'un site plus
  /// ancien que l'appli sert encore.
  static TrainingProgram? parse(Object? raw) {
    try {
      final map = raw is Map && raw['training_program'] is Map
          ? raw['training_program'] as Map
          : raw;
      if (map is! Map) return null;

      final name = map['name'];
      final token = map['share_token'];
      if (name is! String || name.isEmpty) return null;
      if (token is! String || token.isEmpty) return null;

      final rawBlocks = map['blocks'];
      final timeline = rawBlocks is List && rawBlocks.isNotEmpty
          ? _fromBlocks(rawBlocks)
          : _fromLegacyMilestones(map['milestones']);
      if (timeline == null) return null;

      return TrainingProgram(
        id: map['id'] is num ? (map['id'] as num).toInt() : 0,
        name: name,
        shareToken: token,
        milestones: timeline.milestones,
        cues: timeline.cues,
      );
    } catch (e) {
      debugPrint('[entraînement] programme illisible : $e');
      return null;
    }
  }

  /// Un seul bloc illisible (durée absente ou nulle) rend tout le programme
  /// inexploitable : le sauter décalerait tous les suivants.
  static ({List<WorkoutMilestone> milestones, List<WorkoutCue> cues})? _fromBlocks(List rawBlocks) {
    final milestones = <WorkoutMilestone>[];
    final cues = <WorkoutCue>[];
    var offset = 0;

    for (final entry in rawBlocks) {
      if (entry is! Map) return null;
      final duration = entry['duration_seconds'];
      if (duration is! num || duration < 1) return null;

      milestones.add(WorkoutMilestone.fromMap(entry, offset));
      _addCue(cues, entry['start_sound'], entry['start_cue_timing'], offset, WorkoutCueTiming.at);
      offset += duration.toInt();
      _addCue(cues, entry['end_sound'], entry['end_cue_timing'], offset, WorkoutCueTiming.before);
    }

    milestones.add(WorkoutMilestone.closing(offset));
    return (milestones: milestones, cues: cues);
  }

  static void _addCue(
    List<WorkoutCue> cues,
    Object? rawSound,
    Object? rawTiming,
    int boundarySeconds,
    WorkoutCueTiming fallback,
  ) {
    final sound = WorkoutSound.parse(rawSound);
    if (sound == null) return;
    cues.add(WorkoutCue(
      boundarySeconds: boundarySeconds,
      sound: sound,
      timing: WorkoutCueTiming.parse(rawTiming, fallback: fallback),
    ));
  }

  /// L'ancien format : chaque jalon porte son son, annoncé en avance par
  /// défaut (`before`). Le dernier jalon, qui n'ouvre aucun bloc, garde sa
  /// place dans la timeline (nom et cibles inclus) comme avant.
  static ({List<WorkoutMilestone> milestones, List<WorkoutCue> cues})? _fromLegacyMilestones(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;

    final milestones = <WorkoutMilestone>[];
    final cues = <WorkoutCue>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final offset = entry['offset_seconds'];
      if (offset is! num || offset < 0) continue;
      milestones.add(WorkoutMilestone.fromMap(entry, offset.toInt()));
      _addCue(cues, entry['sound'], entry['cue_timing'], offset.toInt(), WorkoutCueTiming.before);
    }

    if (milestones.isEmpty || milestones.first.offsetSeconds != 0) return null;
    for (var i = 1; i < milestones.length; i++) {
      if (milestones[i].offsetSeconds <= milestones[i - 1].offsetSeconds) return null;
    }
    return (milestones: milestones, cues: cues);
  }
}
