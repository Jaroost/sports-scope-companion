package ch.logicraft.sports.companion

import android.content.ComponentName
import android.content.Context
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Les commandes `media_*` du profil : pilote le lecteur de musique du téléphone.
 *
 * Le volume règle le flux musique directement. Pour piste et lecture/pause, on
 * s'adresse à la session média d'une *autre* appli quand l'accès aux
 * notifications est accordé (voir [RemoteSessionListener]) : notre propre session
 * `SportsScopeRemote` est souvent devant (télécommande assignée) et recevrait
 * sinon la touche à la place du lecteur. Sans cet accès, repli sur une touche
 * média système ; [lastKeyDispatchMs] permet alors à [RemoteKeys] d'ignorer
 * l'écho si c'est notre session qui la reçoit, au lieu de boucler.
 */
class MediaControl(context: Context, messenger: BinaryMessenger) {

    private val appContext = context.applicationContext
    private val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val sessions =
        appContext.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val listener = ComponentName(appContext, RemoteSessionListener::class.java)

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "command") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            when (call.arguments as? String) {
                "media_volume_up" -> volume(AudioManager.ADJUST_RAISE)
                "media_volume_down" -> volume(AudioManager.ADJUST_LOWER)
                "media_next" -> transport(KeyEvent.KEYCODE_MEDIA_NEXT)
                "media_previous" -> transport(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
                "media_play_pause" -> transport(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            }
            result.success(null)
        }
    }

    private fun volume(direction: Int) {
        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
    }

    private fun foreignController(): MediaController? {
        val granted = android.provider.Settings.Secure
            .getString(appContext.contentResolver, "enabled_notification_listeners")
            ?.contains(listener.flattenToString()) == true
        if (!granted) return null
        return try {
            sessions.getActiveSessions(listener)
                .firstOrNull { it.packageName != appContext.packageName }
        } catch (_: SecurityException) {
            null
        }
    }

    private fun transport(keyCode: Int) {
        val controller = foreignController()
        if (controller != null) {
            val controls = controller.transportControls
            when (keyCode) {
                KeyEvent.KEYCODE_MEDIA_NEXT -> controls.skipToNext()
                KeyEvent.KEYCODE_MEDIA_PREVIOUS -> controls.skipToPrevious()
                else ->
                    if (controller.playbackState?.state == PlaybackState.STATE_PLAYING) controls.pause()
                    else controls.play()
            }
            return
        }
        lastKeyDispatchMs = SystemClock.elapsedRealtime()
        for (action in intArrayOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            audio.dispatchMediaKeyEvent(KeyEvent(action, keyCode))
        }
    }

    companion object {
        private const val CHANNEL = "sports_scope/media"

        /** Instant de la dernière touche média envoyée par repli (voir [RemoteKeys]). */
        @Volatile
        var lastKeyDispatchMs = 0L
    }
}
