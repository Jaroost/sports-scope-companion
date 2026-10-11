import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ride/offline_map_state.dart';
import '../ui/offline_download_dialog.dart';
import 'navigation_target.dart';

enum BackgroundDownloadStatus { running, done, failed }

@immutable
class BackgroundDownload {
  const BackgroundDownload(
    this.status, {
    this.pct = 0,
    this.phase = '',
  });

  final BackgroundDownloadStatus status;
  final int pct;

  /// L'étape, déjà traduite par le site (voir `OfflineMapState.phase`).
  final String phase;
}

/// Télécharge la carte hors ligne d'un itinéraire **sans ouvrir la navigation**.
///
/// Même principe que `RouteCatalogFetch` : un WebView invisible, jamais attaché à
/// l'arbre de widgets, qui partage le stockage du WebView de navigation — c'est
/// ce qui fait que l'archive écrite ici (OPFS) est retrouvée là-bas sans rien
/// copier. Il charge `/routes/<token>/offline` (`OfflineDownloader.vue`), une page
/// sans carte, sans GPS, et surtout **sans toucher à la session de navigation
/// mémorisée** : charger la vraie page de navigation écraserait le tracé que
/// « Continuer l'itinéraire en cours » est censé reprendre.
///
/// **L'utilisateur choisit les fonds.** La page publie son état par le même message
/// `offline` que la navigation — dont la liste des fonds, déjà pré-cochés d'après
/// les pays traversés — et ATTEND. On montre ce état dans la boîte « Carte hors
/// ligne » habituelle ([showOfflineDownloadDialog]) : cases à cocher, estimation,
/// Télécharger. Fermer la boîte pendant le téléchargement le laisse courir (la
/// liste en montre l'avancement) ; la fermer avant de l'avoir lancé jette le
/// WebView.
///
/// Un seul à la fois — chaque téléchargement fait travailler un WebView entier
/// (décodage d'images, assemblage de l'archive en mémoire), et deux de front sur
/// un téléphone de milieu de gamme finiraient par en perdre un.
///
/// **Limite connue** : tout se passe dans le processus de l'appli, sans service
/// au premier plan. Au premier plan ou écran allumé, ça va ; rangée dans la
/// poche, Android peut la suspendre et le téléchargement s'arrête avec elle.
class OfflineBackgroundDownloads extends ChangeNotifier {
  OfflineBackgroundDownloads({
    this.baseUrl = sportsScopeBaseUrl,
    this.loadTimeout = const Duration(seconds: 45),
    this.stallTimeout = const Duration(minutes: 3),
  });

  static final instance = OfflineBackgroundDownloads();

  final String baseUrl;

  /// Temps accordé à la page pour annoncer qu'elle peut archiver (chargement,
  /// lecture du tracé). Au-delà, on abandonne : réseau absent ou itinéraire
  /// introuvable.
  final Duration loadTimeout;

  /// Silence toléré une fois le téléchargement lancé. Il n'y a pas de durée
  /// maximale — un long itinéraire en demande — mais plus aucun message depuis
  /// trois minutes, c'est un WebView mort.
  final Duration stallTimeout;

  static const _channel = 'SportsScopeCompanion';

  /// L'état que montre la boîte : celui de la page, ou « chargement ».
  final OfflineMapNotifier state = OfflineMapNotifier();

  final Map<String, BackgroundDownload> _downloads = {};

  /// Le jeton en cours de traitement, `null` au repos.
  String? _active;
  WebViewController? _controller;
  Timer? _watchdog;
  DateTime _lastMessage = DateTime.now();
  DateTime _startedAt = DateTime.now();
  bool _supportedSeen = false;

  /// L'utilisateur a pressé « Télécharger » : avant, la page attend ses choix.
  bool _started = false;
  bool _dialogOpen = false;

  BackgroundDownload? of(String token) => _downloads[token];

  bool get busy => _active != null;

  /// Ouvre la boîte de choix des fonds pour [token] — et charge la page derrière si
  /// ce n'est pas déjà fait. Si ce jeton est déjà en cours, la boîte montre son
  /// avancement. Sans effet si un autre jeton occupe le WebView.
  Future<void> open(BuildContext context, String token) async {
    if (_active != null && _active != token) return;
    if (_dialogOpen) return;
    if (_active == null) _begin(token);

    _dialogOpen = true;
    await showOfflineDownloadDialog(
      context,
      state: state,
      start: _start,
      cancel: () => unawaited(_cancel(token)),
      remove: () => unawaited(_command('offlineRemove')),
      toggleLayer: (id) => unawaited(_toggleLayer(id)),
    );
    _dialogOpen = false;

    // Fermée sans avoir rien lancé (ou après la fin) : plus rien à attendre.
    if (_active == token && !_started) {
      _downloads.remove(token);
      _teardown();
      notifyListeners();
    } else if (_active == token && _downloads[token]?.status != BackgroundDownloadStatus.running) {
      _teardown();
      notifyListeners();
    }
  }

  void _begin(String token) {
    _active = token;
    _started = false;
    _supportedSeen = false;
    _startedAt = _lastMessage = DateTime.now();
    state.value = const OfflineMapState.loading();
    notifyListeners();

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          _channel,
          onMessageReceived: (message) => _onMessage(token, message.message),
        )
        ..setNavigationDelegate(NavigationDelegate(
          onWebResourceError: (error) {
            // Seul le document principal compte : une ressource manquée est
            // ordinaire (voir `RouteCatalogFetch`).
            if (error.isForMainFrame != true) return;
            _finish(token, BackgroundDownloadStatus.failed);
          },
        ));
      _controller = controller;
      _watchdog = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkStalled(token),
      );
      unawaited(controller
          .loadRequest(Uri.parse('$baseUrl/routes/$token/offline'))
          .catchError((Object e) {
        debugPrint('[hors ligne] chargement impossible : $e');
        _finish(token, BackgroundDownloadStatus.failed);
      }));
    } catch (e) {
      debugPrint('[hors ligne] démarrage impossible : $e');
      _finish(token, BackgroundDownloadStatus.failed);
    }
  }

  void _start() {
    final token = _active;
    if (token == null) return;
    _started = true;
    _lastMessage = DateTime.now();
    _downloads[token] =
        const BackgroundDownload(BackgroundDownloadStatus.running);
    notifyListeners();
    unawaited(_command('offlineStart'));
  }

  /// Interrompt le téléchargement de [token] : la page l'annule de son côté (rien
  /// d'écrit à moitié) et republie ses choix. On garde le WebView : la boîte, toujours
  /// ouverte, redevient celle du choix des fonds — c'est sa fermeture qui le jettera.
  Future<void> _cancel(String token) async {
    if (_active != token) return;
    _started = false;
    _downloads.remove(token);
    notifyListeners();
    await _command('offlineCancel');
  }

  Future<void> _toggleLayer(String id) async {
    try {
      await _controller?.runJavaScript(
        'void (window.sportsScopeCompanion?.offlineToggleLayer?.(${jsonEncode(id)}));',
      );
    } catch (e) {
      debugPrint('[hors ligne] choix de couche ignoré : $e');
    }
  }

  Future<void> _command(String method) async {
    try {
      await _controller?.runJavaScript(
        'void (window.sportsScopeCompanion?.$method?.());',
      );
    } catch (e) {
      debugPrint('[hors ligne] commande ignorée : $e');
    }
  }

  void _onMessage(String token, String raw) {
    if (_active != token) return;
    final OfflineMapState? next;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      next = OfflineMapState.fromJson(decoded);
    } catch (_) {
      return;
    }
    if (next == null) return;
    _lastMessage = DateTime.now();

    // Tant que la page n'a pas lu le tracé (`supported` faux), la boîte garde son
    // « chargement » : lui montrer cet état-là dirait « rien à archiver ».
    if (!next.supported && !next.errored) return;
    state.value = next;

    if (next.errored) {
      _finish(token, BackgroundDownloadStatus.failed);
      return;
    }
    _supportedSeen = true;
    if (!_started) return; // la page attend les choix de l'utilisateur

    // Archive à jour et plus rien en cours : elle vient d'être écrite. `downloading`
    // exclut le faux départ d'un multi-fonds où le premier fond est prêt avant le
    // dernier ; `missing`, une couche cochée pas encore faite.
    if (next.ready && !next.stale && !next.missing && !next.downloading) {
      _finish(token, BackgroundDownloadStatus.done);
      return;
    }

    _downloads[token] = BackgroundDownload(
      BackgroundDownloadStatus.running,
      pct: next.pct,
      phase: next.phase,
    );
    notifyListeners();
  }

  void _checkStalled(String token) {
    if (_active != token) return;
    final now = DateTime.now();
    // Avant le lancement, la page attend l'utilisateur : seul le chargement a un délai.
    if (_supportedSeen && !_started) return;
    final limit = _supportedSeen ? stallTimeout : loadTimeout;
    final since = _supportedSeen ? _lastMessage : _startedAt;
    if (now.difference(since) > limit) {
      debugPrint('[hors ligne] sans nouvelles depuis ${limit.inSeconds} s');
      _finish(token, BackgroundDownloadStatus.failed);
    }
  }

  void _finish(String token, BackgroundDownloadStatus status) {
    if (_active != token) return;
    final previous = _downloads[token];
    _downloads[token] = BackgroundDownload(
      status,
      pct: status == BackgroundDownloadStatus.done ? 100 : previous?.pct ?? 0,
    );
    if (status == BackgroundDownloadStatus.failed && state.value?.errored != true) {
      state.value = const OfflineMapState.failed();
    }
    // La boîte peut encore être ouverte sur « terminé » ou « échec » (et son bouton
    // Supprimer a besoin de la page) : c'est à sa fermeture qu'on jette le WebView.
    if (!_dialogOpen) _teardown();
    notifyListeners();
  }

  void _teardown() {
    _watchdog?.cancel();
    _watchdog = null;
    // `about:blank` plutôt qu'un simple oubli : la page tient un WebView, des
    // images décodées et l'archive en mémoire, qu'il faut laisser partir tout
    // de suite et non au prochain passage du ramasse-miettes.
    unawaited(_controller?.loadRequest(Uri.parse('about:blank')));
    _controller = null;
    _active = null;
    _started = false;
  }
}
