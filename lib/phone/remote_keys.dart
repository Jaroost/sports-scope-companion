import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Les cinq touches qu'une télécommande média sait produire, vues du profil de
/// sortie (`ButtonSettings.remote`). Plusieurs codes natifs peuvent désigner la
/// même touche : certaines télécommandes envoient `PLAY` et `PAUSE` séparés,
/// d'autres `PLAY_PAUSE`, d'autres encore le bouton de kit mains libres.
enum RemoteKey {
  volumeUp('volume_up'),
  volumeDown('volume_down'),
  next('next'),
  previous('previous'),
  playPause('play_pause');

  const RemoteKey(this.token);

  /// Le suffixe de la clé du document (`remote_<token>` dans `buttons`) — le
  /// même que celui que le site assainit (`CompanionSettings::REMOTE_KEYS`).
  final String token;

  String get settingsKey => 'remote_$token';

  /// Le volume ne livre qu'une impulsion par pression, sans relâchement : ses
  /// gestes se déduisent du rythme des impulsions, pas d'un appui et d'un
  /// relâchement (voir `RemoteVolumePulsePolicy`).
  bool get isVolume => this == volumeUp || this == volumeDown;

  /// `null` pour une touche que ce banc ne connaît pas — jamais une erreur.
  static RemoteKey? ofNative(String key) => switch (key) {
        'VOLUME_UP' || 'KEYCODE_VOLUME_UP' => volumeUp,
        'VOLUME_DOWN' || 'KEYCODE_VOLUME_DOWN' => volumeDown,
        'KEYCODE_MEDIA_NEXT' => next,
        'KEYCODE_MEDIA_PREVIOUS' => previous,
        'KEYCODE_MEDIA_PLAY_PAUSE' ||
        'KEYCODE_MEDIA_PLAY' ||
        'KEYCODE_MEDIA_PAUSE' ||
        'KEYCODE_HEADSETHOOK' =>
          playPause,
        _ => null,
      };
}

/// Une touche venue d'une télécommande Bluetooth, telle que le natif la livre.
class RemoteKeyEvent {
  const RemoteKeyEvent({
    required this.source,
    required this.key,
    this.action,
    this.repeat,
    this.time,
    this.device,
  });

  /// `status` (`ORDER_*` : rang de notre session dans la liste d'Android, qui
  /// n'est pas l'ordre des touches — jamais une touche), `accessibility` (lecture/pause vue par le service d'accessibilité, avant
  /// l'assistant : la seule voie qui livre l'appui long), `media` (session
  /// média : lecture, suivant…), `volume` (sens d'une
  /// pression, via le fournisseur de volume) ou `activity` (touche vue par la
  /// fenêtre avant son routage, appli au premier plan — la seule à dire de quel
  /// appareil elle vient).
  final String source;
  final String key;

  /// `down`/`up`. Absent pour `volume`, qui ne rend que le sens.
  final String? action;
  final int? repeat;
  final DateTime? time;

  /// L'appareil d'origine, en toutes lettres (voir `RemoteKeys.deviceOf`). Pour
  /// le banc d'essai seulement : rien n'en dépend encore.
  final String? device;

  /// Tolérant : un événement incompréhensible rend `null` plutôt que de lever,
  /// même convention que les décodeurs GATT.
  static RemoteKeyEvent? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final source = raw['source'];
    final key = raw['key'];
    if (source is! String || key is! String) return null;
    final millis = raw['time'];
    return RemoteKeyEvent(
      source: source,
      key: key,
      action: raw['action'] as String?,
      repeat: (raw['repeat'] as num?)?.toInt(),
      device: raw['device'] as String?,
      time: millis is num
          ? DateTime.fromMillisecondsSinceEpoch(millis.toInt())
          : null,
    );
  }

  @override
  String toString() {
    final parts = [
      source,
      key,
      ?action,
      if (repeat != null && repeat! > 0) 'x$repeat',
      ?device,
    ];
    return parts.join(' · ');
  }
}

/// Les touches de la télécommande, via la session média native
/// (`RemoteKeys.kt`). S'abonner active la session, annuler la libère.
class AndroidRemoteKeys {
  const AndroidRemoteKeys();

  static const _events = EventChannel('sports_scope/remote_keys/events');
  static const _control = MethodChannel('sports_scope/remote_keys/control');

  /// Dit au natif quelles touches de volume l'appli garde pour elle. Les autres
  /// règlent le volume du téléphone comme si la session n'existait pas : sans
  /// ça, un profil qui n'assigne que « suivant » rendrait la télécommande muette
  /// pour la musique. À appeler **avant** de s'abonner à [events].
  Future<void> configure({
    required bool captureVolumeUp,
    required bool captureVolumeDown,
  }) async {
    try {
      await _control.invokeMethod<void>('configure', {
        'captureVolumeUp': captureVolumeUp,
        'captureVolumeDown': captureVolumeDown,
      });
    } catch (e) {
      debugPrint('[télécommande] réglage non transmis : $e');
    }
  }

  /// Le service d'accessibilité (`RemoteKeyService.kt`) est-il activé ? C'est lui
  /// qui permet l'appui long sur lecture/pause : sans lui Android l'envoie à
  /// l'assistant et l'appli ne voit que le clic. `false` en cas d'erreur.
  Future<bool> accessibilityEnabled() async {
    try {
      return await _control.invokeMethod<bool>('accessibilityEnabled') ?? false;
    } catch (e) {
      debugPrint('[télécommande] état du service illisible : $e');
      return false;
    }
  }

  /// L'accès aux notifications est-il accordé ? Il permet au natif de lire quelle
  /// session reçoit les touches et de ne reprendre sa place que si besoin.
  Future<bool> notificationAccessGranted() async {
    try {
      return await _control.invokeMethod<bool>('notificationAccessGranted') ??
          false;
    } catch (e) {
      debugPrint('[télécommande] accès notifications illisible : $e');
      return false;
    }
  }

  Future<void> openNotificationAccessSettings() async {
    try {
      await _control.invokeMethod<void>('openNotificationAccessSettings');
    } catch (e) {
      debugPrint('[télécommande] réglages non ouverts : $e');
    }
  }

  /// Ouvre les réglages d'accessibilité, où l'on active le service à la main —
  /// Android n'offre aucun moyen de le faire à la place de l'utilisateur.
  Future<void> openAccessibilitySettings() async {
    try {
      await _control.invokeMethod<void>('openAccessibilitySettings');
    } catch (e) {
      debugPrint('[télécommande] réglages non ouverts : $e');
    }
  }

  Stream<RemoteKeyEvent> events() => _events
      .receiveBroadcastStream()
      .map(RemoteKeyEvent.fromChannel)
      .where((event) => event != null)
      .cast<RemoteKeyEvent>()
      .handleError(
          (Object e) => debugPrint('[télécommande] flux en erreur : $e'));
}
