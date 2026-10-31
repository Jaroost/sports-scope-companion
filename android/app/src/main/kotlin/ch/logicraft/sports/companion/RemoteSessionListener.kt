package ch.logicraft.sports.companion

import android.service.notification.NotificationListenerService

/**
 * Coquille vide : n'existe que pour que l'utilisateur puisse accorder l'« accès
 * aux notifications ». `MediaSessionManager.getActiveSessions` l'exige pour
 * lister les sessions média du téléphone, dans l'ordre où Android leur adresse
 * les touches — c'est ce qui permet à [RemoteKeys] de savoir si sa session est
 * vraiment devant, au lieu de reprendre sa place à l'aveugle. Aucune
 * notification n'est lue.
 */
class RemoteSessionListener : NotificationListenerService()
