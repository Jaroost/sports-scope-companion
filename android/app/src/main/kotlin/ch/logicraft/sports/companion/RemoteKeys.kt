package ch.logicraft.sports.companion

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.SystemClock
import android.media.AudioTrack
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Les touches d'une télécommande Bluetooth (volume, lecture, suivant…), offertes
 * à Dart en flux — **banc d'essai** : on veut voir ce que la télécommande envoie
 * vraiment avant de lui donner un rôle (`RemoteKeysDebugPage`).
 *
 * Une télécommande média est vue par Android comme un clavier HID ou comme un
 * contrôleur AVRCP, jamais comme un capteur GATT : `flutter_blue_plus` ne la voit
 * pas. Les touches média sont livrées à la **dernière session média active** ;
 * d'où cette `MediaSession`, qui n'a aucun son à piloter et n'existe que pour
 * être la destinataire. Elle se déclare « en lecture », sinon Android préfère
 * une autre appli de musique pour les touches.
 *
 * Le volume suit un autre chemin : sans [VolumeProvider], le système règle
 * lui-même le volume et ne prévient personne. Une session à volume « distant »
 * relatif reçoit à la place le sens de chaque pression.
 *
 * Rien ne tourne tant que Dart n'est pas abonné : la session s'active au premier
 * abonné et se libère à l'annulation, pour ne pas voler les touches de la
 * musique en dehors des essais.
 */
class RemoteKeys(context: Context, messenger: BinaryMessenger) {

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())

    private var session: MediaSession? = null
    private var silence: AudioTrack? = null
    private var sink: EventChannel.EventSink? = null

    private val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var lastReclaimMs = 0L

    /**
     * Les touches de volume que l'appli garde pour elle. Les autres sont
     * rendues au système ([AudioManager.adjustStreamVolume]) : la session les a
     * prises avec le reste, mais sans action assignée la télécommande doit
     * continuer de régler la musique. Tout est capté par défaut (banc d'essai).
     */
    private var captureVolumeUp = true
    private var captureVolumeDown = true

    /**
     * Une autre appli qui se met à jouer (ou en reprend) nous repasse derrière
     * elle pour les touches média : la destinataire est la dernière session
     * passée « en lecture », et la musique démarre le plus souvent *après* la
     * nôtre. On le sait par `AudioManager`, qui prévient à chaque changement de
     * lecture audio du téléphone — et on reprend la place aussitôt.
     */
    private val playbackWatcher = object : AudioManager.AudioPlaybackCallback() {
        override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>) {
            // Notre propre silence déclenche aussi ce rappel, et reprendre la
            // place le relance : le délai coupe la boucle.
            val now = SystemClock.elapsedRealtime()
            if (now - lastReclaimMs < RECLAIM_COOLDOWN_MS) return
            reclaim()
        }
    }

    init {
        MethodChannel(messenger, "$NAMESPACE/control").setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    captureVolumeUp = call.argument<Boolean>("captureVolumeUp") ?: true
                    captureVolumeDown = call.argument<Boolean>("captureVolumeDown") ?: true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "$NAMESPACE/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                    start()
                }

                override fun onCancel(arguments: Any?) {
                    stop()
                    sink = null
                }
            }
        )
    }

    private fun start() {
        if (session != null) return
        val created = MediaSession(appContext, "SportsScopeRemote")

        @Suppress("DEPRECATION")
        created.setFlags(
            MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
        )

        created.setCallback(object : MediaSession.Callback() {
            override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                val event = keyEventOf(mediaButtonIntent) ?: return false
                emit(
                    mapOf(
                        "source" to "media",
                        "key" to KeyEvent.keyCodeToString(event.keyCode),
                        "code" to event.keyCode,
                        "action" to if (event.action == KeyEvent.ACTION_DOWN) "down" else "up",
                        "repeat" to event.repeatCount,
                    )
                )
                // Consommé : sans ça, la même touche déclencherait aussi la
                // lecture/pause d'une autre appli, ce que le banc doit éviter.
                return true
            }
        }, main)

        // Volume « distant » relatif : on reçoit le sens (+1, -1) de chaque
        // pression au lieu que le système règle le volume du téléphone.
        created.setPlaybackToRemote(
            object : VolumeProvider(VOLUME_CONTROL_RELATIVE, 100, 50) {
                override fun onAdjustVolume(direction: Int) {
                    val captured = if (direction > 0) captureVolumeUp else captureVolumeDown
                    if (direction != 0 && !captured) {
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            if (direction > 0) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                            AudioManager.FLAG_SHOW_UI,
                        )
                        return
                    }
                    emit(
                        mapOf(
                            "source" to "volume",
                            "key" to when {
                                direction > 0 -> "VOLUME_UP"
                                direction < 0 -> "VOLUME_DOWN"
                                else -> "VOLUME_SAME"
                            },
                            "direction" to direction,
                        )
                    )
                }
            }
        )

        created.isActive = true
        session = created
        setState(PlaybackState.STATE_PLAYING)
        startSilence()
        audio.registerAudioPlaybackCallback(playbackWatcher, main)
    }

    private fun setState(state: Int) {
        session?.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_STOP
                )
                .setState(state, 0, 1f)
                .build()
        )
    }

    /**
     * Repasser par « pause » avant « lecture » : Android ne réordonne les
     * sessions que sur le *passage* à l'état actif, redire « lecture » à une
     * session déjà en lecture ne change rien.
     */
    private fun reclaim() {
        if (session == null) return
        lastReclaimMs = SystemClock.elapsedRealtime()
        setState(PlaybackState.STATE_PAUSED)
        setState(PlaybackState.STATE_PLAYING)
    }

    /**
     * Un silence en boucle, pour de vrai. Déclarer la session « en lecture » ne
     * suffit pas : mesuré avec la télécommande, le volume nous arrivait mais
     * suivant/précédent/pause allaient au lecteur de musique. Android route les
     * touches média vers la session qui a **réellement** joué du son en dernier ;
     * tant que la nôtre ne produit rien, une appli de musique la devance.
     *
     * Pas de focus audio demandé, exprès : la musique du cycliste continue de
     * jouer, seules ses touches de télécommande changent de destinataire.
     */
    private fun startSilence() {
        if (silence != null) return
        val frames = SILENCE_RATE
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SILENCE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(frames * 2)
            .build()
        track.write(ShortArray(frames), 0, frames)
        track.setLoopPoints(0, frames, -1)
        track.play()
        silence = track
    }

    private fun stop() {
        audio.unregisterAudioPlaybackCallback(playbackWatcher)
        silence?.run {
            stop()
            release()
        }
        silence = null
        session?.run {
            isActive = false
            release()
        }
        session = null
        // Le banc d'essai (qui ne règle rien) reprend tout, d'une sortie à l'autre.
        captureVolumeUp = true
        captureVolumeDown = true
    }

    private fun emit(event: Map<String, Any>) {
        // Les rappels arrivent déjà sur le thread principal (le Handler donné à
        // setCallback), mais le VolumeProvider, lui, n'a pas de Handler.
        main.post { sink?.success(event + ("time" to System.currentTimeMillis())) }
    }

    private fun keyEventOf(intent: Intent): KeyEvent? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
        }

    companion object {
        private const val NAMESPACE = "sports_scope/remote_keys"
        private const val SILENCE_RATE = 8000
        private const val RECLAIM_COOLDOWN_MS = 1500L
    }
}
