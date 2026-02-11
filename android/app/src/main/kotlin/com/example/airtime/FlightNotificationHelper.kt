package com.example.airtime

import android.content.Context
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class FlightNotificationHelper(private val context: Context) {

    fun show(params: Map<String, Any?>) {
        val notificationId = params["notificationId"] as Int
        val title = params["title"] as String
        val contentLine = params["contentLine"] as String
        val expandedText = params["expandedText"] as String
        val route = params["route"] as String
        val progress = params["progress"] as Int
        val useChronometer = params["useChronometer"] as Boolean
        val chronometerWhen = (params["chronometerWhen"] as Number).toLong()
        val countDown = params["countDown"] as Boolean
        val originCity = params["originCity"] as String
        val destinationCity = params["destinationCity"] as String

        // Extract status from title (e.g., "AI101 — On Time" → "On Time")
        val status = title.substringAfter(" \u2014 ", title)

        // Build subtitle by stripping the route prefix from contentLine
        val routeStr = "$originCity \u2192 $destinationCity"
        val subtitle = contentLine
            .removePrefix("$routeStr \u00B7 ")
            .removePrefix("$routeStr ")
            .trim()
            .ifEmpty { contentLine }

        // Status color: green by default, orange for delays, red for cancelled
        val statusColor = when {
            status.startsWith("Delayed") -> 0xFFFF9800.toInt()
            status == "Cancelled" -> 0xFFF44336.toInt()
            status.startsWith("Diverted") -> 0xFFFF9800.toInt()
            else -> 0xFF4CAF50.toInt()
        }

        // === Collapsed RemoteViews (flight path design) ===
        val collapsed = RemoteViews(context.packageName, R.layout.notification_flight_collapsed)
        collapsed.setTextViewText(R.id.origin_code, originCity)
        collapsed.setTextViewText(R.id.dest_code, destinationCity)
        collapsed.setTextViewText(R.id.notification_status, status)
        collapsed.setTextViewText(R.id.notification_subtitle, subtitle)
        collapsed.setTextColor(R.id.notification_status, statusColor)
        collapsed.setProgressBar(R.id.notification_progress, 100, progress, false)

        // Position the flight icon at the progress edge
        val dm = context.resources.displayMetrics
        val density = dm.density
        val screenWidthDp = dm.widthPixels / density
        // Estimate progress bar width: screen - system chrome (~80dp) - city text+dots (~130dp)
        val progressBarWidthPx = ((screenWidthDp - 210f) * density).toInt().coerceAtLeast(1)
        val iconHalfPx = (9 * density).toInt()
        val paddingStartPx = ((progressBarWidthPx * progress / 100f) - iconHalfPx)
            .toInt().coerceAtLeast(0)
        collapsed.setViewPadding(R.id.flight_icon_container, paddingStartPx, 0, 0, 0)

        // === Expanded RemoteViews (flight tracker design) ===
        val expanded = RemoteViews(context.packageName, R.layout.notification_flight_expanded)
        val flightNumber = params["flightNumber"] as String
        val departureTime = params["departureTime"] as String
        val arrivalTime = params["arrivalTime"] as String

        expanded.setTextViewText(R.id.exp_flight_number, flightNumber)
        expanded.setTextViewText(R.id.exp_arrival_info, "$arrivalTime  $destinationCity")
        expanded.setTextViewText(R.id.exp_departure_info, "$originCity  $departureTime")
        expanded.setTextViewText(R.id.exp_status, status)
        expanded.setTextColor(R.id.exp_status, statusColor)
        expanded.setTextViewText(R.id.exp_details, expandedText)
        expanded.setProgressBar(R.id.exp_progress, 100, progress, false)

        // Compute time remaining from chronometerWhen
        val phaseLabel = when {
            status == "Landed" || status == "Cancelled" || status.startsWith("Diverted") -> ""
            status == "In Flight" -> "until arrival"
            else -> "until departure"
        }
        val timeRemaining = if (phaseLabel.isNotEmpty() && useChronometer && chronometerWhen > System.currentTimeMillis()) {
            val totalMinutes = ((chronometerWhen - System.currentTimeMillis()) / 60000).toInt()
            val hours = totalMinutes / 60
            val mins = totalMinutes % 60
            if (hours > 0) "${hours}h ${mins}m $phaseLabel" else "${mins}m $phaseLabel"
        } else ""
        expanded.setTextViewText(R.id.exp_time_remaining, timeRemaining)

        // Position airplane icon on expanded flight path
        val expProgressWidthPx = ((screenWidthDp - 100f) * density).toInt().coerceAtLeast(1)
        val expPaddingPx = ((expProgressWidthPx * progress / 100f) - iconHalfPx)
            .toInt().coerceAtLeast(0)
        expanded.setViewPadding(R.id.exp_flight_icon_container, expPaddingPx, 0, 0, 0)

        val builder = NotificationCompat.Builder(context, "flight_tracking_live")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setOngoing(true)
            .setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(0xFF4CAF50.toInt())
            .setShowWhen(useChronometer)

        if (useChronometer) {
            builder.setUsesChronometer(true)
                .setWhen(chronometerWhen)
                .setChronometerCountDown(countDown)
        }

        NotificationManagerCompat.from(context).notify(notificationId, builder.build())
    }

    fun cancel(notificationId: Int) {
        NotificationManagerCompat.from(context).cancel(notificationId)
    }
}
