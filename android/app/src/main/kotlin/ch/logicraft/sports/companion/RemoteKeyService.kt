package ch.logicraft.sports.companion

import android.accessibilityservice.AccessibilityService
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * Voit les touches lecture/pause de la télécommande **avant** qu'Android ne les
 * traite — c'est la seule place où l'on peut empêcher l'appui long de lancer
 * l'assistant (Gemini).
 *
 * Android traite play/pause comme une « touche vocale » : il attend lui-même le
 * délai d'appui long, et s'il est atteint il ouvre l'assistant sans rien livrer à
 * la `MediaSession` ; relâchée avant, la touche n'arrive que comme un clic.
 * Aucun appui long n'est donc observable depuis la session. Un service
 * d'accessibilité qui filtre les touches (`flagRequestFilterKeyEvents`) passe
 * devant ce traitement, et en consommant la touche on le lui retire.
 *
 * Il ne fait rien tant que [RemoteKeys] n'a pas posé [listener] (une sortie dont
 * le profil assigne des touches) : hors sortie, la télécommande garde son
 * comportement d'origine, assistant compris. Il ne touche non plus qu'aux
 * touches lecture/pause de la télécommande ([RemoteKeys.isRemoteDevice]).
 */
class RemoteKeyService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (!isPlayPause(event.keyCode)) return false
        val handler = listener ?: return false
        if (!RemoteKeys.isRemoteDevice(event.device)) return false
        return handler(event)
    }

    private fun isPlayPause(code: Int) =
        code == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE || code == KeyEvent.KEYCODE_HEADSETHOOK ||
            code == KeyEvent.KEYCODE_MEDIA_PLAY || code == KeyEvent.KEYCODE_MEDIA_PAUSE

    companion object {
        /** Posé par [RemoteKeys] ; rend `true` quand la touche est consommée. */
        @Volatile
        var listener: ((KeyEvent) -> Boolean)? = null

        @Volatile
        private var instance: RemoteKeyService? = null

        /** Le service est-il activé (et lié) dans les réglages d'accessibilité ? */
        val isEnabled: Boolean get() = instance != null
    }
}
