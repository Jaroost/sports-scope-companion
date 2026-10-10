import 'package:flutter/foundation.dart';

/// Un morceau de l'aperçu d'un itinéraire : un tracé de pente homogène, en coordonnées
/// d'une boîte de 100 × 100 (`routes.preview_segments` côté site, le même dessin que la
/// liste des itinéraires). [category] : 0 plat, 1 montée, 2 descente. [path] reste la
/// chaîne SVG du site (`M1.0,2.0 L3.0,4.0 …`) : le cache la garde telle quelle, et c'est
/// `RoutePreview` qui la lit au dessin.
@immutable
class RoutePreviewSegment {
  const RoutePreviewSegment(this.category, this.path);

  final int category;
  final String path;

  static List<RoutePreviewSegment> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map && entry['c'] is num && entry['d'] is String)
          RoutePreviewSegment((entry['c'] as num).toInt(), entry['d'] as String),
    ];
  }
}

/// Un itinéraire du site, réduit à ce qu'il faut pour le choisir et le
/// naviguer.
///
/// Le [shareToken] n'est pas un détail d'implémentation : c'est **la seule clé
/// dont l'appli ait besoin**, parce que la navigation est adressée par lui côté
/// Rails et pas par l'identifiant interne. Elle n'a donc rien à authentifier
/// pour ouvrir un tracé une fois qu'elle en connaît le jeton. Tous les
/// itinéraires en ont un (`has_secure_token`, colonne non nulle) : aucun n'est
/// hors de portée.
@immutable
class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.name,
    required this.shareToken,
    this.distanceM = 0,
    this.elevationGainM = 0,
    this.activity,
    this.updatedAt,
    this.previewSegments = const [],
  });

  final int id;
  final String name;
  final String shareToken;
  final double distanceM;
  final double elevationGainM;

  /// `cycling`, `mtb` ou `hiking`. Nulle si le site en ajoute une qu'on ne
  /// connaît pas encore — auquel cas la ligne s'affiche sans pictogramme plutôt
  /// que de disparaître.
  final String? activity;

  final DateTime? updatedAt;

  /// L'aperçu du tracé, vide quand le site n'en a pas (tracé trop court) ou qu'il est plus
  /// ancien que l'appli — la ligne montre alors son pictogramme comme avant.
  final List<RoutePreviewSegment> previewSegments;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'share_token': shareToken,
        'distance_m': distanceM,
        'elevation_gain_m': elevationGainM,
        'activity': activity,
        'updated_at': updatedAt?.toIso8601String(),
        'preview_segments': [
          for (final s in previewSegments) {'c': s.category, 'd': s.path},
        ],
      };

  /// Décode une entrée de `/api/routes`. Tolérant : ce qui manque vaut zéro, ce
  /// qui est illisible vaut `null` — une réponse un peu différente de ce qu'on
  /// attend ne doit pas vider la liste entière.
  ///
  /// Deux champs font exception et rendent `null` : le nom et le jeton. Sans
  /// nom, la ligne serait inchoisissable ; sans jeton, elle serait inouvrable.
  static RouteSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final name = raw['name'];
    final token = raw['share_token'];
    if (name is! String || name.isEmpty) return null;
    if (token is! String || token.isEmpty) return null;

    return RouteSummary(
      id: raw['id'] is num ? (raw['id'] as num).toInt() : 0,
      name: name,
      shareToken: token,
      distanceM: _toDouble(raw['distance_m']) ?? 0,
      elevationGainM: _toDouble(raw['elevation_gain_m']) ?? 0,
      activity: raw['activity'] is String ? raw['activity'] as String : null,
      updatedAt: raw['updated_at'] is String
          ? DateTime.tryParse(raw['updated_at'] as String)
          : null,
      previewSegments: RoutePreviewSegment.listFrom(raw['preview_segments']),
    );
  }

  /// Décode la charge utile complète de `/api/routes`.
  ///
  /// La forme sans pagination — celle que réclame aussi le sélecteur de la page
  /// web — rend `{routes: [...], opened: [...], total: n}`. On ne garde que
  /// `routes` : `opened` est un historique de consultation, pas un catalogue.
  static List<RouteSummary> listFromPayload(Object? raw) {
    final routes = raw is Map ? raw['routes'] : raw;
    if (routes is! List) return const [];

    return [
      for (final entry in routes)
        if (RouteSummary.fromJson(entry) case final route?) route,
    ];
  }

  static double? _toDouble(Object? raw) => raw is num ? raw.toDouble() : null;
}
