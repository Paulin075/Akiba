package com.example.akiba

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Activité principale.
 *
 * FlutterFragmentActivity est exigé par local_auth (prompt biométrique).
 * Elle porte aussi le pont SMS : un SMS détecté hors application est déposé
 * dans l'Intent de la notification, puis remis à Dart (méthode
 * `consumePendingSms`, ou flux `akiba/sms_events` si l'application tourne
 * déjà). Aucun SMS n'est stocké sur disque.
 */
class MainActivity : FlutterFragmentActivity() {

    private var pendingSms: String? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readSmsExtra(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readSmsExtra(intent)
        val body = pendingSms
        if (body != null && eventSink != null) {
            pendingSms = null
            eventSink?.success(body)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingSms" -> {
                        result.success(pendingSms)
                        pendingSms = null
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun readSmsExtra(intent: Intent?) {
        val body = intent?.getStringExtra(SmsReceiver.EXTRA_SMS_BODY)
        if (body.isNullOrBlank()) return
        pendingSms = body
        intent.removeExtra(SmsReceiver.EXTRA_SMS_BODY)
    }

    companion object {
        private const val CHANNEL = "akiba/sms"
        private const val EVENTS = "akiba/sms_events"
    }
}
