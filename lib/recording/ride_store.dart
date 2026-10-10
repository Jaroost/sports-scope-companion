import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ride_session.dart';
import 'track_point.dart';

/// Les sorties enregistrées, sur le disque de l'application.
///
/// Un dossier par sortie :
///
/// ```
/// rides/2026-07-28T14-03-11Z/session.json   ← le résumé
/// rides/2026-07-28T14-03-11Z/points.jsonl   ← un point par ligne, en ajout
/// ```
///
/// Pas de base de données : l'écriture est purement séquentielle (on ajoute une
/// ligne par seconde, on ne relit jamais pendant la sortie), et un fichier en
/// mode ajout est ce qui résiste le mieux à une coupure — au pire la dernière
/// ligne est tronquée, tout ce qui précède reste lisible. C'est aussi ce qui
/// permet d'aller récupérer une sortie à la main sur le téléphone.
class RideStore {
  RideStore(this.root);

  /// Ouvre le magasin standard de l'appli. À n'appeler qu'après
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<RideStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return RideStore(Directory(p.join(directory.path, 'rides')));
  }

  final Directory root;

  static const _metaName = 'session.json';
  static const _pointsName = 'points.jsonl';
  static const _previewName = 'preview.json';

  /// Nombre de sommets gardés pour l'aperçu d'une sortie dans la liste : de quoi en dessiner
  /// la forme dans une pastille de quelques centimètres, sans relire 20 000 points.
  static const _previewVertices = 80;

  Directory directoryFor(String id) => Directory(p.join(root.path, id));

  File pointsFileFor(String id) =>
      File(p.join(root.path, id, _pointsName));

  File _metaFileFor(String id) => File(p.join(root.path, id, _metaName));

  /// Crée le dossier d'une nouvelle sortie et son résumé initial.
  ///
  /// Le résumé est écrit *avant* le premier point : une sortie qui s'interrompt
  /// au bout de dix secondes doit quand même apparaître dans la liste, ne
  /// serait-ce que pour être supprimée.
  Future<RideSession> create({DateTime? at}) async {
    final startedAt = (at ?? DateTime.now()).toUtc();
    final session = RideSession(id: RideSession.idFor(startedAt), startedAt: startedAt);
    await directoryFor(session.id).create(recursive: true);
    await save(session);
    return session;
  }

  /// Réécrit le résumé d'une sortie.
  ///
  /// Écriture directe, sans fichier temporaire : le résumé est réécrit en
  /// permanence pendant la sortie et se reconstruit de toute façon à partir des
  /// points ([_recover]). Le protéger comme le catalogue d'appareils serait
  /// payer une écriture double pour une donnée redondante.
  Future<void> save(RideSession session) async {
    try {
      final file = _metaFileFor(session.id);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(session.toJson()), flush: true);
    } catch (e) {
      // Perdre le résumé ne doit pas interrompre une sortie en cours : les
      // points, eux, continuent d'être écrits.
      debugPrint('[rides] résumé non écrit (${session.id}) : $e');
    }
  }

  /// Note qu'une sortie est partie sur le site. Relit le résumé **sur le disque** plutôt que
  /// de repartir d'une copie en mémoire : la sortie qui roule réécrit le sien en permanence.
  Future<void> markSynced(String id, {DateTime? at}) async {
    try {
      final file = _metaFileFor(id);
      if (!await file.exists()) return;
      final session = RideSession.fromJson(jsonDecode(await file.readAsString()));
      if (session == null) return;
      await save(session.copyWith(syncedAt: (at ?? DateTime.now()).toUtc()));
    } catch (e) {
      debugPrint('[rides] synchro non notée ($id) : $e');
    }
  }

  /// Les sorties connues, de la plus récente à la plus ancienne.
  Future<List<RideSession>> list() async {
    if (!await root.exists()) return [];

    final sessions = <RideSession>[];
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final session = await _read(p.basename(entry.path));
      if (session != null) sessions.add(session);
    }
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  Future<RideSession?> _read(String id) async {
    try {
      final file = _metaFileFor(id);
      if (!await file.exists()) return null;
      final session = RideSession.fromJson(jsonDecode(await file.readAsString()));
      if (session == null) return null;
      // Une sortie non terminée a un résumé forcément en retard sur ses points
      // (il n'est réécrit que périodiquement) : on le reconstruit pour ne pas
      // annoncer 12 km à une sortie qui en a enregistré 14.
      return session.isFinished ? session : await _recover(session);
    } catch (e) {
      debugPrint('[rides] sortie illisible ($id), ignorée : $e');
      return null;
    }
  }

  /// Recalcule les compteurs d'une sortie interrompue depuis ses points.
  Future<RideSession> _recover(RideSession session) async {
    final points = await this.points(session.id);
    if (points.isEmpty) return session;
    return session.copyWith(
      pointCount: points.length,
      distanceM: points.last.distanceM,
      // Un point par seconde enregistrée : les compter *est* le temps de
      // chronomètre, pauses comprises puisqu'on n'écrit rien en pause.
      movingSeconds: points.length,
    );
  }

  /// Tous les points d'une sortie, dans l'ordre d'écriture.
  ///
  /// Les lignes illisibles sont sautées une par une — voir [TrackPoint.fromJson]
  /// pour la dernière ligne, toujours suspecte après une coupure.
  Future<List<TrackPoint>> points(String id) async {
    final file = pointsFileFor(id);
    if (!await file.exists()) return [];

    final points = <TrackPoint>[];
    final lines = await file.readAsLines();
    for (final line in lines) {
      if (line.isEmpty) continue;
      try {
        final point = TrackPoint.fromJson(jsonDecode(line));
        if (point != null) points.add(point);
      } catch (_) {
        continue;
      }
    }
    return points;
  }

  /// La forme d'une sortie, en `[lat, lng]` réduits à ~[_previewVertices] sommets — pour la
  /// petite pastille de la liste « Mes sorties ».
  ///
  /// Relire les points d'une sortie coûte (un point par seconde, une sortie de 6 h en a plus de
  /// 20 000) : la forme réduite est donc **rangée à côté de la sortie** (`preview.json`) et relue
  /// de là ensuite. [cache] n'est vrai que pour une sortie terminée — celle qui roule encore
  /// grandit à chaque tic, on la recalcule plutôt que de figer un tracé en retard.
  Future<List<List<double>>> preview(String id, {required bool cache}) async {
    final stored = File(p.join(root.path, id, _previewName));
    if (cache) {
      try {
        if (await stored.exists()) {
          final decoded = jsonDecode(await stored.readAsString());
          if (decoded is List) {
            return [
              for (final pair in decoded)
                if (pair is List && pair.length == 2 && pair[0] is num && pair[1] is num)
                  [(pair[0] as num).toDouble(), (pair[1] as num).toDouble()],
            ];
          }
        }
      } catch (_) {
        // Un aperçu illisible se recalcule : rien de précieux dedans.
      }
    }

    final located = [
      for (final point in await points(id))
        if (point.lat != null && point.lng != null) [point.lat!, point.lng!],
    ];
    final step = located.length <= _previewVertices ? 1 : (located.length - 1) / (_previewVertices - 1);
    final reduced = located.length <= _previewVertices
        ? located
        : [for (var i = 0; i < _previewVertices; i++) located[(i * step).round()]];

    if (cache && reduced.length >= 2) {
      try {
        await stored.writeAsString(jsonEncode(reduced));
      } catch (e) {
        debugPrint('[rides] aperçu non écrit ($id) : $e');
      }
    }
    return reduced;
  }

  /// Ouvre le fichier de points en ajout.
  ///
  /// En ajout et jamais en écrasement : reprendre une sortie après un
  /// redémarrage de l'appli doit compléter le fichier, pas l'effacer.
  Future<IOSink> openPoints(String id) async {
    final file = pointsFileFor(id);
    await file.parent.create(recursive: true);
    return file.openWrite(mode: FileMode.append);
  }

  Future<void> delete(String id) async {
    final directory = directoryFor(id);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
