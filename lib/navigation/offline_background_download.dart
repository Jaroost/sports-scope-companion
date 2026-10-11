import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ride/offline_map_state.dart';
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
/// La page lance elle-même le téléchargement et publie son état par le même
/// message `offline` que la navigation : cette classe ne fait qu'observer et
/// conclure. Un seul à la fois — chaque téléchargement fait travailler un
/// WebView entier (décodage d'images, assemblage de l'archive en mémoire), et
/// deux de front sur un téléphone de milieu de gamme finiraient par en perdre un.
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

  final Map<String, BackgroundDownload> _downloads = {};

  /// Le jeton en cours de traitement, `null` au repos.
  String? _active;
  WebViewController? _controller;
  Timer? _watchdog;
  DateTime _lastMessage = DateTime.now();
  DateTime _startedAt = DateTime.now();
  bool _supportedSeen = false;

  BackgroundDownload? of(String token) => _downloads[token];

  bool get busy => _active != null;

  /// Lance le téléchargement de [token]. Sans effet si un autre est en cours.
  Future<void> start(String token) async {
    if (_active != null) return;
    _active = token;
    _supportedSeen = false;
    _startedAt = _lastMessage = DateTime.now();
    _downloads[token] =
        const BackgroundDownload(BackgroundDownloadStatus.running);
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
      await controller
          .loadRequest(Uri.parse('$baseUrl/routes/$token/offline'));
    } catch (e) {
      debugPrint('[hors ligne] démarrage impossible : $e');
      _finish(token, BackgroundDownloadStatus.failed);
    }
  }

  /// Interrompt le téléchargement en cours de [token] : la page l'annule de son
  /// côté (rien d'écrit à moitié), puis on jette le WebView.
  Future<void> cancel(String token) async {
    if (_active != token) return;
    try {
      await _controller?.runJavaScript(
        'void (window.sportsScopeCompanion?.offlineCancel?.());',
      );
    } catch (e) {
      debugPrint('[hors ligne] annulation ignorée : $e');
    }
    _downloads.remove(token);
    _teardown();
    notifyListeners();
  }

  void _onMessage(String token, String raw) {
    if (_active != token) return;
    final OfflineMapState? state;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      state = OfflineMapState.fromJson(decoded);
    } catch (_) {
      return;
    }
    if (state == null) return;
    _lastMessage = DateTime.now();

    if (state.errored) {
      _finish(token, BackgroundDownloadStatus.failed);
      return;
    }
    if (!state.supported) return; // la page n'a pas encore lu le tracé
    _supportedSeen = true;

    // Archive à jour et plus rien en cours : soit elle l'était déjà (la page ne
    // lance alors rien), soit elle vient d'être écrite. `downloading` exclut le
    // faux départ d'un multi-fonds où le premier fond est prêt avant le dernier.
    if (state.ready && !state.stale && !state.missing && !state.downloading) {
      _finish(token, BackgroundDownloadStatus.done);
      return;
    }

    _downloads[token] = BackgroundDownload(
      BackgroundDownloadStatus.running,
      pct: state.pct,
      phase: state.phase,
    );
    notifyListeners();
  }

  void _checkStalled(String token) {
    if (_active != token) return;
    final now = DateTime.now();
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
    _teardown();
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
  }
}
