package com.example.airtime

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.airtime/flight_notification"
    private lateinit var notificationHelper: FlightNotificationHelper

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationHelper = FlightNotificationHelper(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showFlightNotification" -> {
                        try {
                            @Suppress("UNCHECKED_CAST")
                            val params = call.arguments as Map<String, Any?>
                            notificationHelper.show(params)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHOW_ERROR", e.message, null)
                        }
                    }
                    "cancelFlightNotification" -> {
                        try {
                            val id = call.arguments as Int
                            notificationHelper.cancel(id)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("CANCEL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
