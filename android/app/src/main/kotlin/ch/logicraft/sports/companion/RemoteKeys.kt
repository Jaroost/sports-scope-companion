package ch.logicraft.sports.companion

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.SystemClock
import android.media.AudioTrack
import android.media.VolumeProvider
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.InputDevice
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
            // Notre propre reprise de place provoque aussi ce rappel, tout de
            // suite après : on l'ignore pour ne pas boucler. Tout autre
            // changement est différé et non jeté : le rappel part quand le son
            // de l'autre appli démarre, mais sa *session* ne passe « en lecture »
            // que quelques instants plus tard — reprendre la place aussitôt la
            // laisserait devant nous.
            if (SystemClock.elapsedRealtime() - lastReclaimMs < SELF_CALLBACK_MS) return
            scheduleReclaim()
        }
    }

    private val sessionManager =
        appContext.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val listenerComponent = ComponentName(appContext, RemoteSessionListener::class.java)
    private var reclaimCount = 0
    private var lastStatus: String? = null

    /** L'accès aux notifications est-il accordé (il rend les sessions lisibles) ? */
    private fun listenerGranted(): Boolean =
        android.provider.Settings.Secure
            .getString(appContext.contentResolver, "enabled_notification_listeners")
            ?.contains(listenerComponent.flattenToString()) == true

    /** Les sessions média, la destinataire des touches en tête ; `null` si illisible. */
    private fun activeSessions(): List<MediaController>? =
        if (!listenerGranted()) null
        else try {
            sessionManager.getActiveSessions(listenerComponent)
        } catch (_: SecurityException) {
            null
        }

    /**
     * Notre session est-elle celle qui reçoit les touches ? `null` : on ne peut
     * pas le savoir (accès aux notifications non accordé).
     */
    private fun isFront(): Boolean? {
        val mine = session?.sessionToken ?: return null
        val first = activeSessions()?.firstOrNull() ?: return null
        return first.sessionToken == mine
    }

    /**
     * Reprend la place seulement si on n'est pas devant, puis revérifie et dit à
     * Dart ce qu'il en est. Sans accès aux notifications, on ne sait pas : on
     * reprend à l'aveugle, comme avant.
     */
    private fun ensureFront() {
        if (session == null) return
        // L'ordre des sessions n'est pas celui des touches (voir
        // [restartSilence]) : on ne s'en sert pas pour décider de s'abstenir.
        reclaim()
        reclaimCount++
        main.removeCallbacks(verifyTask)
        main.postDelayed(verifyTask, VERIFY_DELAY_MS)
    }

    private val verifyTask = Runnable { if (session != null) publishStatus(isFront()) }

    /** Une ligne par *changement* : le banc d'essai n'a pas à être noyé. */
    private fun publishStatus(front: Boolean?) {
        val owner = activeSessions()?.firstOrNull()?.packageName
        val key = when (front) {
            true -> "ORDER_FIRST"
            false -> "ORDER_OTHER"
            null -> "ORDER_UNKNOWN"
        }
        val signature = "$key|$owner|$reclaimCount"
        if (signature == lastStatus) return
        lastStatus = signature
        emit(
            mapOf(
                "source" to "status",
                "key" to key,
                "device" to "destinataire=${owner ?: "?"} reprises=$reclaimCount",
            )
        )
    }

    private val reclaimTask = Runnable { ensureFront() }

    /**
     * Filet : les rappels ne couvrent pas tous les cas (musique lancée appli en
     * arrière-plan, session qui passe devant sans changement audio visible).
     * Reprendre la place à intervalle régulier garantit qu'on ne reste jamais
     * longtemps derrière une autre appli. La session n'a ni interface ni son :
     * la bascule pause/lecture ne se voit nulle part.
     */
    private val periodicReclaim = object : Runnable {
        override fun run() {
            if (session == null) return
            ensureFront()
            main.postDelayed(this, PERIODIC_RECLAIM_MS)
        }
    }

    private fun scheduleReclaim() {
        main.removeCallbacks(reclaimTask)
        for (delay in RECLAIM_DELAYS_MS) main.postDelayed(reclaimTask, delay)
    }

    init {
        MethodChannel(messenger, "$NAMESPACE/control").setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    captureVolumeUp = call.argument<Boolean>("captureVolumeUp") ?: true
                    captureVolumeDown = call.argument<Boolean>("captureVolumeDown") ?: true
                    result.success(null)
                }
                "accessibilityEnabled" -> result.success(RemoteKeyService.isEnabled)
                "notificationAccessGranted" -> result.success(listenerGranted())
                "openNotificationAccessSettings" -> {
                    appContext.startActivity(
                        Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "openAccessibilitySettings" -> {
                    appContext.startActivity(
                        Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
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
                        "device" to deviceOf(event),
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
        main.postDelayed(periodicReclaim, PERIODIC_RECLAIM_MS)

        // Lecture/pause passe d'abord par le service d'accessibilité s'il est
        // activé : c'est le seul chemin où l'appui long n'ouvre pas l'assistant.
        // Consommée là, la touche n'atteint plus la session (pas de doublon) ;
        // sans le service, elle suit la session comme avant.
        RemoteKeyService.listener = { event ->
            emit(
                mapOf(
                    "source" to "accessibility",
                    "key" to KeyEvent.keyCodeToString(event.keyCode),
                    "code" to event.keyCode,
                    "action" to if (event.action == KeyEvent.ACTION_DOWN) "down" else "up",
                    "repeat" to event.repeatCount,
                    "device" to deviceOf(event),
                )
            )
            true
        }
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
        restartSilence()
    }

    /**
     * Android adresse les touches média à l'appli qui a **démarré** du son en
     * dernier. Un silence qui tourne en boucle depuis le début ne redémarre
     * jamais : dès qu'une musique démarre après lui, elle passe devant, et
     * l'état de la session n'y change rien. Il faut l'arrêter puis le relancer
     * — en deux temps, sinon le système fusionne les deux changements et ne voit
     * aucun démarrage.
     */
    private fun restartSilence() {
        val track = silence ?: return
        try {
            track.pause()
        } catch (_: IllegalStateException) {
            return
        }
        main.removeCallbacks(resumeSilenceTask)
        main.postDelayed(resumeSilenceTask, SILENCE_GAP_MS)
    }

    private val resumeSilenceTask = Runnable {
        try {
            silence?.play()
        } catch (_: IllegalStateException) {
        }
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
        main.removeCallbacks(reclaimTask)
        main.removeCallbacks(periodicReclaim)
        main.removeCallbacks(verifyTask)
        main.removeCallbacks(resumeSilenceTask)
        lastStatus = null
        reclaimCount = 0
        // Avant tout : hors session, la télécommande retrouve son assistant.
        RemoteKeyService.listener = null
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

    /**
     * Sonde du banc d'essai : l'appareil d'origine d'une touche vue par la
     * fenêtre, **avant** que le système la route vers la session. C'est le seul
     * moment où l'on peut dire « téléphone » ou « télécommande » : le
     * `VolumeProvider` ne donne que le sens. Ne consomme rien (l'appelant laisse
     * la touche suivre son chemin) et ne dit rien tant que la page de test n'est
     * pas abonnée.
     */
    fun probe(event: KeyEvent) {
        if (sink == null || !isRemoteKey(event.keyCode)) return
        emit(
            mapOf(
                "source" to "activity",
                "key" to KeyEvent.keyCodeToString(event.keyCode),
                "code" to event.keyCode,
                "action" to if (event.action == KeyEvent.ACTION_DOWN) "down" else "up",
                "repeat" to event.repeatCount,
                "device" to deviceOf(event),
            )
        )
    }

    /**
     * Rend au téléphone ses propres boutons de volume. La session prend *tout*
     * le volume, y compris celui des boutons du boîtier, et `VolumeProvider` ne
     * dit pas d'où vient la pression : seule la fenêtre, avant le routage, voit
     * l'appareil. Une pression qui ne vient pas de la télécommande règle donc le
     * volume ici même et est consommée ; celle de la télécommande suit son chemin
     * vers la session.
     *
     * Sans effet hors session (rien n'a été pris, le système règle déjà seul), et
     * pour une touche sans appareil (pile Bluetooth, AVRCP) qu'on ne sait pas
     * attribuer — elle reste à la session. Écran verrouillé, la fenêtre ne voit
     * rien : les boutons du téléphone y restent pris, faute de source.
     */
    fun interceptPhoneVolume(event: KeyEvent): Boolean {
        if (session == null) return false
        val code = event.keyCode
        if (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN) return false
        val device = event.device ?: return false
        if (isRemoteDevice(device)) return false

        if (event.action == KeyEvent.ACTION_DOWN) {
            audio.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                if (code == KeyEvent.KEYCODE_VOLUME_UP) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                AudioManager.FLAG_SHOW_UI,
            )
        }
        return true
    }

    private fun isRemoteKey(code: Int) =
        code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN ||
            code == KeyEvent.KEYCODE_HEADSETHOOK ||
            (code >= KeyEvent.KEYCODE_MEDIA_PLAY && code <= KeyEvent.KEYCODE_MEDIA_PREVIOUS) ||
            code == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE || code == KeyEvent.KEYCODE_MEDIA_STOP

    /**
     * Tout ce qu'Android sait de l'appareil, en une ligne : on ne sait pas encore
     * ce qui distingue le mieux une télécommande du téléphone (nom, fabricant,
     * identifiant), c'est justement ce que la sonde est là pour dire. Un
     * `deviceId` de -1 ou un appareil absent veut dire que la touche n'a pas
     * d'appareil derrière elle (pile Bluetooth, AVRCP).
     */
    private fun deviceOf(event: KeyEvent): String {
        val device: InputDevice? = event.device
        val head = "id=${event.deviceId} src=0x${Integer.toHexString(event.source)}"
        if (device == null) return "$head (aucun appareil)"
        return "$head « ${device.name} » vendor=${device.vendorId} " +
            "product=${device.productId} virtuel=${device.isVirtual}"
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
        private const val SILENCE_GAP_MS = 150L
        private const val VERIFY_DELAY_MS = 400L
        private const val PERIODIC_RECLAIM_MS = 2000L
        private const val SELF_CALLBACK_MS = 300L
        private val RECLAIM_DELAYS_MS = longArrayOf(400L, 1500L)

        /**
         * La télécommande du cycliste, telle que `getevent -il` la voit :
         * « SmartRemote », bus Bluetooth, vendor 0x05ac, produit 0x022c. Le
         * couple plutôt que le nom (trop générique) ou l'`id` (qui change à
         * chaque appairage). Une autre télécommande demande de changer ces deux
         * nombres.
         */
        private const val REMOTE_VENDOR_ID = 0x05ac
        private const val REMOTE_PRODUCT_ID = 0x022c

        fun isRemoteDevice(device: InputDevice?) =
            device != null && device.vendorId == REMOTE_VENDOR_ID &&
                device.productId == REMOTE_PRODUCT_ID
    }
}
