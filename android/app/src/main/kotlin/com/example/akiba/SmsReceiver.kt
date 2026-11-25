package com.example.akiba

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony

/**
 * Récepteur des SMS financiers (Flooz, Mixx by Yas, banques).
 *
 * Rôle strictement limité : reconnaître un SMS de dépôt/crédit ou de
 * retrait/débit, puis afficher une notification **sans montant** qui ouvre
 * l'application sur la fiche préremplie. Le texte du SMS n'est pas écrit sur
 * disque : il voyage uniquement dans l'Intent de la notification, et le
 * montant n'est extrait qu'une fois l'application ouverte (analyse Dart).
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            ?: return
        val body = messages.joinToString(separator = "") { it.messageBody ?: "" }
            .trim()
        if (body.isEmpty()) return
        val sender = messages.firstOrNull()?.originatingAddress ?: ""
        if (!isFinancialSms(sender, body)) return
        notify(context, body)
    }

    private fun isFinancialSms(sender: String, body: String): Boolean {
        val text = "$sender $body".lowercase()
        val knownSource = SOURCES.any { text.contains(it) }
        if (!knownSource) return false
        val hasCurrency = Regex("fcfa|xof|f\\s?cfa|cfa").containsMatchIn(body)
        val hasAmount = Regex("\\d{1,3}([ .]\\d{3})+|\\d+").containsMatchIn(body)
        return hasCurrency && hasAmount
    }

    private fun notify(context: Context, body: String) {
        if (!notificationsAllowed(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SMS financiers AKIBA",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            channel.description =
                "Détection Flooz, Mixx by Yas et banque. Aucun montant affiché."
            manager.createNotificationChannel(channel)
        }

        val open = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN
            putExtra(EXTRA_SMS_BODY, body)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Nouveau SMS financier")
            .setContentText("Touchez pour vérifier et confirmer l’opération.")
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun notificationsAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as? NotificationManager ?: return false
            return manager.areNotificationsEnabled()
        }
        return true
    }

    companion object {
        const val ACTION_OPEN = "com.akiba.action.SMS_OPEN"
        const val EXTRA_SMS_BODY = "akiba.sms.body"
        const val CHANNEL_ID = "akiba_sms"
        const val NOTIFICATION_ID = 4101

        private val SOURCES = listOf(
            "flooz", "moov", "mixx", "yas",
            "orabank", "bank", "banque", "boa", "ecobank", "coris",
            "nsia", "ubs", "bsic", "attijari", "société générale",
            "societe generale", "sgci"
        )
    }
}
