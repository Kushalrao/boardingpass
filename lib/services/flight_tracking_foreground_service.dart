import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ============================================================
// DATA CLASS — passed from main.dart to avoid circular imports
// ============================================================

class FlightTrackingData {
  final String firestoreId;
  final String flightNumber;
  final String originCity;
  final String destinationCity;
  final DateTime departureDateTime;
  final DateTime? arrivalDateTime;
  final String? departureTerminal;
  final String? arrivalTerminal;
  final String? gate;

  FlightTrackingData({
    required this.firestoreId,
    required this.flightNumber,
    required this.originCity,
    required this.destinationCity,
    required this.departureDateTime,
    this.arrivalDateTime,
    this.departureTerminal,
    this.arrivalTerminal,
    this.gate,
  });
}

// ============================================================
// FOREGROUND TASK CALLBACK + HANDLER (must be top-level)
// ============================================================

@pragma('vm:entry-point')
void flightTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(_FlightTrackingTaskHandler());
}

class _FlightTrackingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[FlightTracking] Foreground service started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No polling — updates come via FCM in the main isolate
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[FlightTracking] Foreground service destroyed');
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}
}

// ============================================================
// INTERNAL STATE for a tracked flight
// ============================================================

class _TrackedFlight {
  final String flightNumber;
  final String originCity;
  final String destinationCity;
  final DateTime departureDateTime;
  final DateTime? arrivalDateTime;
  final int notificationId;

  // Mutable state updated by FCM events
  String? gate;
  String? departureTerminal;
  String? arrivalTerminal;
  int? delayMinutes;
  String? status; // null=scheduled, 'departed', 'landed', 'cancelled', 'diverted'
  String? diversionAirport;
  String? baggageBelt;

  _TrackedFlight({
    required this.flightNumber,
    required this.originCity,
    required this.destinationCity,
    required this.departureDateTime,
    this.arrivalDateTime,
    required this.notificationId,
    this.gate,
    this.departureTerminal,
    this.arrivalTerminal,
  });
}

// ============================================================
// MAIN SERVICE — manages foreground service + notifications
// ============================================================

class FlightTrackingForegroundService {
  static final FlightTrackingForegroundService _instance =
      FlightTrackingForegroundService._internal();
  factory FlightTrackingForegroundService() => _instance;
  FlightTrackingForegroundService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.example.airtime/flight_notification');
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Map<String, _TrackedFlight> _trackedFlights = {};
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  bool _initialized = false;

  /// Initialize the service. Call once after Firebase is ready.
  Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isAndroid) return; // Android only for now
    _initialized = true;

    // Set up communication port (safe to call from here)
    FlutterForegroundTask.initCommunicationPort();

    // Configure the foreground task service notification (minimal, keeps service alive)
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'flight_tracking_service',
        channelName: 'Flight Tracking Service',
        channelDescription: 'Keeps flight tracking active in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        allowWakeLock: false,
      ),
    );

    // Create the notification channel for individual flight tracking notifications
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'flight_tracking_live',
          'Live Flight Tracking',
          description: 'Persistent notifications for tracked flights',
          importance: Importance.low,
        ),
      );
    }

    // Listen to FCM messages — separate from existing NotificationService listener
    _fcmSubscription = FirebaseMessaging.onMessage.listen(_handleFcmMessage);

    debugPrint('[FlightTracking] Initialized');
  }

  /// Evaluate flights and start tracking eligible ones.
  /// Call after loading trips from Firestore.
  Future<void> evaluateFlights(List<FlightTrackingData> flights) async {
    if (!Platform.isAndroid || !_initialized) return;

    final now = DateTime.now();
    final cutoff = now.add(const Duration(hours: 24));

    for (final flight in flights) {
      if (flight.firestoreId.isEmpty || flight.flightNumber.isEmpty) continue;

      bool shouldTrack = false;

      if (flight.departureDateTime.isBefore(now)) {
        // Already departed — track if not landed or landed < 30 min ago
        if (flight.arrivalDateTime == null ||
            flight.arrivalDateTime!
                .isAfter(now.subtract(const Duration(minutes: 30)))) {
          shouldTrack = true;
        }
      } else if (flight.departureDateTime.isBefore(cutoff)) {
        // Departing within 24 hours
        shouldTrack = true;
      }

      if (shouldTrack && !_trackedFlights.containsKey(flight.firestoreId)) {
        _addTrackedFlight(flight);
      }
    }

    // Start foreground service if we have flights to track
    if (_trackedFlights.isNotEmpty) {
      await _ensureServiceRunning();
      // Show/refresh notifications for all tracked flights
      for (final id in _trackedFlights.keys) {
        await _showFlightNotification(id);
      }
    }
  }

  void _addTrackedFlight(FlightTrackingData data) {
    // Generate unique notification ID from Firestore doc ID (avoid collision with service ID 900)
    final notificationId = data.firestoreId.hashCode.abs() % 90000 + 10000;

    _trackedFlights[data.firestoreId] = _TrackedFlight(
      flightNumber: data.flightNumber,
      originCity: data.originCity,
      destinationCity: data.destinationCity,
      departureDateTime: data.departureDateTime,
      arrivalDateTime: data.arrivalDateTime,
      notificationId: notificationId,
      gate: data.gate,
      departureTerminal: data.departureTerminal,
      arrivalTerminal: data.arrivalTerminal,
    );

    debugPrint(
        '[FlightTracking] Now tracking ${data.flightNumber} (id: ${data.firestoreId}, notifId: $notificationId)');
  }

  // ============================================================
  // NOTIFICATION CONTENT — builds per flight phase
  // ============================================================

  Future<void> _showFlightNotification(String flightId) async {
    final tracked = _trackedFlights[flightId];
    if (tracked == null) return;

    final now = DateTime.now();
    final departed = tracked.departureDateTime.isBefore(now);
    final landed = tracked.arrivalDateTime != null &&
        tracked.arrivalDateTime!.isBefore(now);

    final route = '${tracked.originCity} \u2192 ${tracked.destinationCity}';

    String title;
    String contentLine;
    String expandedText;
    bool useChronometer = false;
    int chronometerWhen = 0;
    bool countDown = true;
    int progress = 0;

    // Determine notification content based on current phase
    if (tracked.status == 'cancelled') {
      title = '${tracked.flightNumber} \u2014 Cancelled';
      contentLine = '$route flight cancelled';
      expandedText = '$route flight has been cancelled';
    } else if (tracked.status == 'diverted') {
      title = '${tracked.flightNumber} \u2014 Diverted';
      contentLine =
          'Diverted to ${tracked.diversionAirport ?? "unknown"}';
      expandedText =
          'Original: ${tracked.destinationCity} \u00B7 Diverted to: ${tracked.diversionAirport ?? "unknown"}';
      progress = 50;
    } else if (landed || tracked.status == 'landed') {
      title = '${tracked.flightNumber} \u2014 Landed';
      final baggageText = tracked.baggageBelt != null
          ? ' \u00B7 Baggage Belt ${tracked.baggageBelt}'
          : '';
      contentLine = 'Arrived at ${tracked.destinationCity}$baggageText';
      final parts = <String>['Arrived at ${tracked.destinationCity}'];
      if (tracked.arrivalTerminal != null) {
        parts.add('Terminal: ${tracked.arrivalTerminal}');
      }
      if (tracked.baggageBelt != null) {
        parts.add('Baggage: Belt ${tracked.baggageBelt}');
      }
      expandedText = parts.join(' \u00B7 ');
      progress = 100;
    } else if (departed || tracked.status == 'departed') {
      title = '${tracked.flightNumber} \u2014 In Flight';
      contentLine =
          '$route \u00B7 Arriving ${_formatTime(tracked.arrivalDateTime)}';
      expandedText =
          'Departed ${_formatTime(tracked.departureDateTime)} \u00B7 ETA: ${_formatTime(tracked.arrivalDateTime)}';
      if (tracked.arrivalDateTime != null) {
        useChronometer = true;
        chronometerWhen = tracked.arrivalDateTime!.millisecondsSinceEpoch;
        countDown = true;
        final totalMinutes = tracked.arrivalDateTime!
            .difference(tracked.departureDateTime)
            .inMinutes;
        final elapsed =
            now.difference(tracked.departureDateTime).inMinutes;
        progress = totalMinutes > 0
            ? ((elapsed / totalMinutes) * 100).clamp(0, 100).toInt()
            : 50;
      }
    } else {
      // Pre-departure
      final statusText =
          (tracked.delayMinutes != null && tracked.delayMinutes! > 0)
              ? 'Delayed ${tracked.delayMinutes}m'
              : 'On Time';
      title = '${tracked.flightNumber} \u2014 $statusText';

      final gateText =
          tracked.gate != null ? 'Gate ${tracked.gate}' : '';
      final departText =
          'Departs ${_formatTime(tracked.departureDateTime)}';
      contentLine = '$route'
          '${gateText.isNotEmpty ? ' \u00B7 $gateText' : ''}'
          ' \u00B7 $departText';

      final expandParts = <String>[];
      expandParts.add('Gate: ${tracked.gate ?? "TBA"}');
      if (tracked.departureTerminal != null) {
        expandParts.add('Terminal: ${tracked.departureTerminal}');
      }
      expandedText = expandParts.join(' \u00B7 ');

      useChronometer = true;
      chronometerWhen = tracked.departureDateTime.millisecondsSinceEpoch;
      countDown = true;
      progress = 0;
    }

    await _channel.invokeMethod('showFlightNotification', {
      'notificationId': tracked.notificationId,
      'title': title,
      'contentLine': contentLine,
      'expandedText': expandedText,
      'route': route,
      'progress': progress,
      'useChronometer': useChronometer,
      'chronometerWhen': chronometerWhen,
      'countDown': countDown,
      'originCity': tracked.originCity,
      'destinationCity': tracked.destinationCity,
      'flightNumber': tracked.flightNumber,
      'departureTime': _formatTime(tracked.departureDateTime),
      'arrivalTime': _formatTime(tracked.arrivalDateTime),
    });
  }

  // ============================================================
  // FCM HANDLER — updates tracked flight state + notification
  // ============================================================

  void _handleFcmMessage(RemoteMessage message) {
    final data = message.data;
    final fcmFlightNumber = data['flightNumber'] as String?;
    final eventType = data['eventType'] as String?;

    if (fcmFlightNumber == null || eventType == null) return;

    // Find the tracked flight matching this FCM message
    final normalizedFcm =
        fcmFlightNumber.replaceAll(' ', '').toUpperCase();
    String? matchedId;
    for (final entry in _trackedFlights.entries) {
      final normalizedTracked =
          entry.value.flightNumber.replaceAll(' ', '').toUpperCase();
      if (normalizedTracked == normalizedFcm) {
        matchedId = entry.key;
        break;
      }
    }

    if (matchedId == null) return;

    final tracked = _trackedFlights[matchedId]!;
    debugPrint(
        '[FlightTracking] FCM event "$eventType" for ${tracked.flightNumber}');

    // Update state based on event type
    switch (eventType) {
      case 'DELAY':
      case 'DEPARTURE_DELAY':
        tracked.delayMinutes =
            int.tryParse(data['delayMinutes']?.toString() ?? '');
        break;
      case 'GATE_CHANGE':
      case 'GATE_DEPARTURE':
        tracked.gate = data['newGate'] ?? data['gate'];
        break;
      case 'DEPARTURE':
        tracked.status = 'departed';
        break;
      case 'ARRIVAL':
        tracked.status = 'landed';
        _scheduleRemoval(matchedId);
        break;
      case 'CANCELLATION':
        tracked.status = 'cancelled';
        break;
      case 'DIVERSION':
        tracked.status = 'diverted';
        tracked.diversionAirport = data['diversionAirport'];
        break;
      case 'BAGGAGE':
        tracked.baggageBelt = data['baggageBelt'] ?? data['baggage'];
        break;
    }

    // Re-render the notification with updated state
    _showFlightNotification(matchedId);
  }

  // ============================================================
  // LIFECYCLE — service start/stop, scheduled removal
  // ============================================================

  void _scheduleRemoval(String flightId) {
    Future.delayed(const Duration(minutes: 30), () async {
      await _stopTrackingFlight(flightId);
    });
  }

  Future<void> _stopTrackingFlight(String flightId) async {
    final tracked = _trackedFlights.remove(flightId);
    if (tracked != null) {
      await _channel.invokeMethod('cancelFlightNotification', tracked.notificationId);
      debugPrint(
          '[FlightTracking] Stopped tracking ${tracked.flightNumber}');
    }

    if (_trackedFlights.isEmpty) {
      await FlutterForegroundTask.stopService();
      debugPrint('[FlightTracking] No more flights — service stopped');
    }
  }

  Future<void> _ensureServiceRunning() async {
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      serviceId: 900,
      notificationTitle: 'Airtime',
      notificationText: 'Tracking ${_trackedFlights.length} flight(s)',
      callback: flightTrackingCallback,
    );

    debugPrint('[FlightTracking] Foreground service started');
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final amPm = h >= 12 ? 'PM' : 'AM';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$hour12:$m $amPm';
  }

  /// Check if any flights are currently being tracked
  bool get isTracking => _trackedFlights.isNotEmpty;

  /// Get the number of tracked flights
  int get trackedFlightCount => _trackedFlights.length;

  void dispose() {
    _fcmSubscription?.cancel();
  }
}
