import 'package:flutter/foundation.dart';

/// Une couche archivable (swisstopo gris/couleur/satellite, IGN plan/ortho…), telle que
/// `companionBridge.ts` la décrit. `label` arrive déjà traduite par le site : l'appli n'a
/// pas sa propre table de libellés par id, donc un fond de plus côté site s'affiche
/// correctement ici sans mise à jour de l'appli.
@immutable
class OfflineMapLayer {
  const OfflineMapLayer({
    required this.id,
    required this.label,
    required this.ready,
    required this.stale,
    required this.selected,
  });

  final String id;
  final String label;
  final bool ready;
  final bool stale;
  final bool selected;

  static OfflineMapLayer? parse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    if (id is! String || id.isEmpty) return null;
    return OfflineMapLayer(
      id: id,
      // Repli sur l'id : un site plus ancien que `label` (avant ce réglage) ne
      // doit pas afficher une ligne vide.
      label: label is String && label.isNotEmpty ? label : id,
      ready: raw['ready'] == true,
      stale: raw['stale'] == true,
      selected: raw['selected'] == true,
    );
  }
}

/// Ce que la page de navigation dit de la carte hors-ligne du trajet affiché.
///
/// Le téléchargement lui-même (tuiles, archive PMTiles dans l'OPFS) reste entièrement
/// côté site — voir `useOfflineMaps.ts` et `companionBridge.ts` du dépôt Rails. L'appli
/// ne fait que déclencher les gestes que le panneau web propose déjà (démarrer, annuler,
/// supprimer, cocher une couche) et afficher où ça en est, dans son propre menu — le
/// panneau web, lui, est masqué dans l'appli (`appOwnsChrome`).
@immutable
class OfflineMapState {
  const OfflineMapState({
    required this.supported,
    required this.ready,
    required this.stale,
    required this.downloading,
    required this.pct,
    required this.mb,
    required this.tiles,
    required this.errored,
    required this.layers,
    this.phase = '',
    this.missing = false,
    this.loading = false,
    this.bufferM = 0,
    this.bufferChoices = const [],
  });

  /// Page de téléchargement pas encore chargée (téléchargement lancé depuis la liste, avant
  /// que le site ait lu le tracé) : la boîte dit alors « chargement » plutôt que de
  /// proposer un départ qui ne ferait rien. Jamais envoyé par le site.
  const OfflineMapState.loading()
      : supported = true,
        ready = false,
        stale = false,
        downloading = false,
        pct = 0,
        mb = 0,
        tiles = 0,
        errored = false,
        layers = const [],
        phase = '',
        missing = false,
        loading = true,
        bufferM = 0,
        bufferChoices = const [];

  /// Échec avant même d'avoir pu lire le tracé (réseau, itinéraire introuvable).
  const OfflineMapState.failed()
      : supported = true,
        ready = false,
        stale = false,
        downloading = false,
        pct = 0,
        mb = 0,
        tiles = 0,
        errored = true,
        layers = const [],
        phase = '',
        missing = false,
        loading = false,
        bufferM = 0,
        bufferChoices = const [];

  /// Faux hors itinéraire (rien à archiver) ou contre une page trop ancienne
  /// pour connaître ce message : dans les deux cas, la commande ne doit pas
  /// paraître dans le menu.
  final bool supported;

  /// Une archive couvre déjà le tracé affiché.
  final bool ready;

  /// L'archive existe mais le tracé a changé depuis (reroutage, détour) : elle
  /// ne couvre plus tout l'itinéraire.
  final bool stale;

  final bool downloading;
  final int pct;

  /// Estimation avant téléchargement (fonds sélectionnés côté site) ; sans
  /// valeur une fois l'archive prête.
  final double mb;
  final int tiles;

  final bool errored;

  /// Une couche cochée reste à télécharger alors qu'une autre archive est déjà prête
  /// (itinéraire sur deux pays : le fond suisse est là, pas encore le français). Faux
  /// contre un site plus ancien : on retombe sur [ready] et [stale] seuls.
  final bool missing;

  final bool loading;

  /// Marge de chaque côté du tracé pour le prochain téléchargement (m), et celles que le site
  /// propose. Vides contre un site plus ancien : la boîte n'affiche alors pas le réglage.
  final int bufferM;
  final List<int> bufferChoices;

  /// L'étape du téléchargement, déjà traduite par le site (« IGN plan — Assemblage
  /// de l'archive »). Vide hors téléchargement, ou contre un site plus ancien : la
  /// boîte n'affiche alors que le pourcentage. Ce sont les étapes après les tuiles
  /// qui la rendent utile — la barre y reste à 100 % pendant que le travail continue.
  final String phase;

  /// Les fonds archivables et leur sélection courante. Vide contre un site plus ancien
  /// que ce réglage — la boîte replie alors sur son texte d'avant (fond actif, implicite).
  final List<OfflineMapLayer> layers;

  static OfflineMapState? fromJson(Map<dynamic, dynamic> json) {
    if (json['type'] != 'offline') return null;
    final rawLayers = json['layers'];
    return OfflineMapState(
      supported: json['supported'] == true,
      ready: json['ready'] == true,
      stale: json['stale'] == true,
      downloading: json['downloading'] == true,
      pct: json['pct'] is num ? (json['pct'] as num).toInt() : 0,
      mb: json['mb'] is num ? (json['mb'] as num).toDouble() : 0,
      tiles: json['tiles'] is num ? (json['tiles'] as num).toInt() : 0,
      errored: json['errored'] == true,
      missing: json['missing'] == true,
      bufferM: json['bufferM'] is num ? (json['bufferM'] as num).toInt() : 0,
      bufferChoices: json['bufferChoices'] is List
          ? [
              for (final m in json['bufferChoices'] as List)
                if (m is num) m.toInt(),
            ]
          : const [],
      phase: json['phase'] is String ? json['phase'] as String : '',
      layers: rawLayers is List
          ? rawLayers.map(OfflineMapLayer.parse).whereType<OfflineMapLayer>().toList()
          : const [],
    );
  }
}

/// L'état hors-ligne courant, à écouter comme n'importe quelle mesure venue du
/// pont.
class OfflineMapNotifier extends ValueNotifier<OfflineMapState?> {
  OfflineMapNotifier() : super(null);

  /// Range un message venu de la page. Un message illisible est ignoré : on
  /// garde le dernier état valable plutôt que de faire disparaître la commande.
  void accept(Map<dynamic, dynamic> json) {
    final next = OfflineMapState.fromJson(json);
    if (next != null) value = next;
  }

  void reset() => value = null;
}
