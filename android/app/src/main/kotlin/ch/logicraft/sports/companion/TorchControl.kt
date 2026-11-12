package ch.logicraft.sports.companion

import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * La lampe torche du téléphone (commande `toggle_torch` du profil).
 *
 * `CameraManager.setTorchMode` ne demande aucune permission : on n'ouvre pas la
 * caméra, on allume seulement le flash. L'état est suivi par un
 * [CameraManager.TorchCallback] plutôt que mémorisé, parce qu'il peut changer
 * hors de l'appli (tuile rapide du système, autre appli qui prend la caméra).
 *
 * Méthodes : `toggle` (renvoie l'état obtenu) et `state`. Sans flash, ou si la
 * caméra est occupée, on renvoie l'état réel, sans lever d'erreur : une
 * commande ratée ne doit pas casser la sortie.
 */
class TorchControl(context: Context, messenger: BinaryMessenger) {

    private val manager = context.applicationContext.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val cameraId: String? = try {
        manager.cameraIdList.firstOrNull { id ->
            val c = manager.getCameraCharacteristics(id)
            c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        }
    } catch (_: CameraAccessException) {
        null
    }

    @Volatile
    private var on = false

    init {
        manager.registerTorchCallback(object : CameraManager.TorchCallback() {
            override fun onTorchModeChanged(id: String, enabled: Boolean) {
                if (id == cameraId) on = enabled
            }
        }, null)

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "toggle" -> {
                    val id = cameraId
                    if (id != null) {
                        try {
                            manager.setTorchMode(id, !on)
                            on = !on
                        } catch (_: CameraAccessException) {
                            // Caméra occupée : l'état réel reste celui du callback.
                        } catch (_: IllegalArgumentException) {
                        }
                    }
                    result.success(on)
                }
                "state" -> result.success(on)
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL = "sports_scope/torch"
    }
}
