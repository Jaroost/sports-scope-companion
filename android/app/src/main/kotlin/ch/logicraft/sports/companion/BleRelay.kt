package ch.logicraft.sports.companion

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Le téléphone en **périphérique** BLE : il se fait passer pour un capteur de
 * cardio / puissance / vitesse-cadence et rediffuse les trames que Dart lui
 * confie (voir `ble_relay.dart`). C'est la seule voie pour une montre dont la
 * connexion directe au capteur échoue.
 *
 * Méthodes : `start` (liste de capacités, rend `null` ou la raison de l'échec),
 * `stop`, `notify` (uuid de caractéristique + octets). Flux : le nombre
 * d'appareils abonnés.
 *
 * Une trame n'est poussée qu'aux appareils abonnés à sa caractéristique (CCCD),
 * comme le fait un vrai capteur. Les caractéristiques de lecture (fonctionnalités,
 * position du capteur) sont fixes : leurs valeurs doivent seulement rester
 * cohérentes avec les drapeaux des trames rediffusées.
 */
@SuppressLint("MissingPermission") // vérifiée à `start`, voir hasPermission()
class BleRelay(private val context: Context, messenger: BinaryMessenger) {

    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var server: BluetoothGattServer? = null
    private var advertising = false
    private var sink: EventChannel.EventSink? = null

    /** Appareils abonnés, par caractéristique. */
    private val subscribed = HashMap<UUID, MutableSet<BluetoothDevice>>()
    private val characteristics = HashMap<UUID, BluetoothGattCharacteristic>()

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    @Suppress("UNCHECKED_CAST")
                    val kinds = (call.arguments as? List<String>)?.toSet() ?: emptySet()
                    result.success(start(kinds))
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                "notify" -> {
                    val uuid = call.argument<String>("uuid")
                    val value = call.argument<ByteArray>("value")
                    if (uuid != null && value != null) notify(uuid, value)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, SUBSCRIBERS_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                publishCount()
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    /** Libère le serveur quand le moteur Flutter disparaît (voir MainActivity). */
    fun shutdown() = stop()

    private fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            (context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED &&
                context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED)

    private fun start(kinds: Set<String>): String? {
        stop()
        if (!hasPermission()) return "Autorise « Appareils à proximité » pour relayer"
        val adapter = manager.adapter
        if (adapter == null || !adapter.isEnabled) return "Bluetooth éteint"
        val advertiser = adapter.bluetoothLeAdvertiser
            ?: return "Ce téléphone ne sait pas se rendre visible en Bluetooth"

        val gatt = manager.openGattServer(context, callback) ?: return "Serveur Bluetooth indisponible"
        server = gatt

        val services = ArrayList<BluetoothGattService>()
        if ("heartRate" in kinds) services += addHeartRate()
        if ("power" in kinds) services += addPower()
        if ("speedCadence" in kinds) services += addCsc()
        if (services.isEmpty()) {
            stop()
            return "Aucune information à relayer"
        }

        // Android n'accepte qu'un `addService` à la fois : un second appel avant
        // `onServiceAdded` est refusé en silence. L'annonce promettait alors un
        // service absent, et la montre, qui voyait le capteur, échouait à s'y
        // connecter. On les pose donc un par un, et on n'annonce qu'à la fin.
        pending.clear()
        pending.addAll(services)
        pendingAdvertiser = advertiser
        addNextService()
        return null
    }

    private val pending = ArrayDeque<BluetoothGattService>()
    private var pendingAdvertiser: android.bluetooth.le.BluetoothLeAdvertiser? = null
    private val announced = ArrayList<UUID>()

    private fun addNextService() {
        val gatt = server ?: return
        val next = pending.removeFirstOrNull()
        if (next == null) {
            startAdvertising()
            return
        }
        if (!gatt.addService(next)) {
            // Refusé d'emblée : ne pas l'annoncer, mais ne pas bloquer les autres.
            addNextService()
        }
    }

    /**
     * Une annonce par service, chacune avec sa propre adresse. Mesuré : annoncés
     * ensemble, puissance et vitesse/cadence font un seul « capteur de
     * puissance » pour une Forerunner, qui ne s'abonne qu'à la puissance et
     * n'affiche jamais la cadence. Séparés, elle peut appairer chacun pour ce
     * qu'il est. Le serveur GATT reste unique.
     */
    private fun startAdvertising() {
        val advertiser = pendingAdvertiser ?: return
        if (announced.isEmpty()) return
        val scanResponse = AdvertiseData.Builder().setIncludeDeviceName(true).build()
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        for (uuid in announced) {
            val data = AdvertiseData.Builder().setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(uuid)).build()
            val callback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                    android.util.Log.i("relay", "annonce ok $uuid")
                }

                override fun onStartFailure(errorCode: Int) {
                    android.util.Log.e("relay", "annonce échec $uuid code=$errorCode")
                }
            }
            advertiseCallbacks += callback
            advertiser.startAdvertising(settings, data, scanResponse, callback)
        }
        advertising = true
    }

    private val advertiseCallbacks = ArrayList<AdvertiseCallback>()

    private fun stop() {
        pending.clear()
        announced.clear()
        if (advertising) {
            val advertiser = manager.adapter?.bluetoothLeAdvertiser
            advertiseCallbacks.forEach { advertiser?.stopAdvertising(it) }
            advertiseCallbacks.clear()
            advertising = false
        }
        server?.close()
        server = null
        subscribed.clear()
        characteristics.clear()
        publishCount()
    }

    private fun notify(uuid: String, value: ByteArray) {
        val id = UUID.fromString(longUuid(uuid))
        val characteristic = characteristics[id] ?: return
        val gatt = server ?: return
        val targets = subscribed[id] ?: return
        for (device in targets.toList()) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.notifyCharacteristicChanged(device, characteristic, false, value)
                } else {
                    @Suppress("DEPRECATION")
                    characteristic.value = value
                    @Suppress("DEPRECATION")
                    gatt.notifyCharacteristicChanged(device, characteristic, false)
                }
            } catch (_: Exception) {
                // Un abonné qui vient de partir : son déconnexion arrive par le callback.
            }
        }
    }

    // --- Services ---------------------------------------------------------

    private fun addHeartRate(): BluetoothGattService {
        val service = BluetoothGattService(sig(0x180D), BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(measurement(0x2A37))
        // Position du capteur : 1 = poitrine. Facultative, mais certaines montres
        // la lisent avant de s'abonner.
        service.addCharacteristic(readOnly(0x2A38, byteArrayOf(1)))
        return service
    }

    private fun addPower(): BluetoothGattService {
        val service = BluetoothGattService(sig(0x1818), BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(measurement(0x2A63))
        // Fonctionnalités : équilibre (bit 0), couple cumulé (1), roue (2),
        // manivelle (3). Les drapeaux de chaque trame disent ce qu'elle porte
        // vraiment ; déclarer large évite qu'une montre ignore la cadence.
        service.addCharacteristic(readOnly(0x2A65, byteArrayOf(0x0F, 0, 0, 0)))
        // Position du capteur : 5 = pédalier... valeur « autre » (0) par prudence.
        service.addCharacteristic(readOnly(0x2A5D, byteArrayOf(0)))
        return service
    }

    private fun addCsc(): BluetoothGattService {
        val service = BluetoothGattService(sig(0x1816), BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(measurement(0x2A5B))
        // Roue (bit 0) et manivelle (bit 1).
        service.addCharacteristic(readOnly(0x2A5C, byteArrayOf(0x03, 0)))
        return service
    }

    private fun measurement(short: Int): BluetoothGattCharacteristic {
        val c = BluetoothGattCharacteristic(
            sig(short),
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            0,
        )
        c.addDescriptor(
            BluetoothGattDescriptor(
                sig(0x2902),
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        characteristics[c.uuid] = c
        return c
    }

    private fun readOnly(short: Int, value: ByteArray): BluetoothGattCharacteristic {
        val c = BluetoothGattCharacteristic(
            sig(short),
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ,
        )
        @Suppress("DEPRECATION")
        c.value = value
        return c
    }

    // --- Callbacks --------------------------------------------------------

    private val callback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            android.util.Log.i("relay", "service ${service.uuid} status=$status")
            main.post {
                if (status == BluetoothGatt.GATT_SUCCESS) announced += service.uuid
                addNextService()
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            android.util.Log.i("relay", "connexion ${device.address} status=$status state=$newState")
            if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                subscribed.values.forEach { it.remove(device) }
                publishCount()
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic,
        ) {
            android.util.Log.i("relay", "lecture ${characteristic.uuid} offset=$offset")
            @Suppress("DEPRECATION")
            val value = characteristic.value ?: ByteArray(0)
            val slice = if (offset <= value.size) value.copyOfRange(offset, value.size) else ByteArray(0)
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, slice)
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice, requestId: Int, offset: Int, descriptor: BluetoothGattDescriptor,
        ) {
            val on = subscribed[descriptor.characteristic.uuid]?.contains(device) == true
            val value = if (on) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray,
        ) {
            val id = descriptor.characteristic.uuid
            android.util.Log.i("relay", "abonnement ${device.address} $id valeur=${value.joinToString { "%02x".format(it) }}")
            val enable = value.isNotEmpty() && value[0].toInt() and 0x01 != 0
            val set = subscribed.getOrPut(id) { HashSet() }
            if (enable) set.add(device) else set.remove(device)
            if (responseNeeded) {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
            }
            publishCount()
        }
    }

    private fun publishCount() {
        val devices = subscribed.values.flatten().toSet().size
        main.post { sink?.success(devices) }
    }

    companion object {
        const val CHANNEL = "sports_scope/relay"
        const val SUBSCRIBERS_CHANNEL = "sports_scope/relay/subscribers"

        private fun sig(short: Int): UUID =
            UUID.fromString(String.format("0000%04x-0000-1000-8000-00805f9b34fb", short))

        /** Dart envoie la forme courte (« 2a63 ») ou longue ; on veut toujours la longue. */
        private fun longUuid(uuid: String): String =
            if (uuid.length <= 4) String.format("0000%4s-0000-1000-8000-00805f9b34fb", uuid).replace(' ', '0') else uuid
    }
}
