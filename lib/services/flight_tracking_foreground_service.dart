import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final int? delayMinutes;
  // iOS Live Activity needs airport codes
  final String? originAirport;
  final String? destinationAirport;
  final String? baggageBelt;

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
    this.delayMinutes,
    this.originAirport,
    this.destinationAirport,
    this.baggageBelt,
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
  final String? originAirport;
  final String? destinationAirport;

  // Mutable state updated by FCM events
  String? gate;
  String? departureTerminal;
  String? arrivalTerminal;
  int? delayMinutes;
  String? status; // null=scheduled, 'departed', 'landed', 'cancelled', 'diverted'
  String? diversionAirport;
  String? baggageBelt;

  // iOS Live Activity state
  String? liveActivityId;

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
    this.originAirport,
    this.destinationAirport,
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

  // Android MethodChannel (existing)
  static const MethodChannel _androidChannel =
      MethodChannel('com.example.airtime/flight_notification');

  // iOS MethodChannel (new)
  static const MethodChannel _iosChannel =
      MethodChannel('com.example.airtime/live_activity');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Map<String, _TrackedFlight> _trackedFlights = {};
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  bool _initialized = false;

  /// Initialize the service. Call once after Firebase is ready.
  Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _initialized = true;

    if (Platform.isAndroid) {
      await _initAndroid();
    } else if (Platform.isIOS) {
      _initIOS();
    }

    // Listen to FCM messages — separate from existing NotificationService listener
    _fcmSubscription = FirebaseMessaging.onMessage.listen(_handleFcmMessage);

    debugPrint('[FlightTracking] Initialized (${Platform.isIOS ? "iOS" : "Android"})');
  }

  Future<void> _initAndroid() async {
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
  }

  void _initIOS() {
    // Listen for push token updates from native side
    _iosChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPushTokenUpdate') {
        final args = call.arguments as Map;
        final flightId = args['flightId'] as String;
        final pushToken = args['pushToken'] as String;
        debugPrint('[FlightTracking] iOS push token for $flightId: $pushToken');
        await _storeLiveActivityPushToken(flightId, pushToken);
      }
    });
  }

  /// Evaluate flights and start tracking eligible ones.
  /// Call after loading trips from Firestore.
  Future<void> evaluateFlights(List<FlightTrackingData> flights) async {
    if (!_initialized) return;

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

    // Start tracking
    if (_trackedFlights.isNotEmpty) {
      if (Platform.isAndroid) {
        await _ensureServiceRunning();
      }
      for (final id in _trackedFlights.keys) {
        if (Platform.isAndroid) {
          await _showFlightNotification(id);
        } else if (Platform.isIOS) {
          await _startOrUpdateLiveActivity(id);
        }
      }
    }
  }

  void _addTrackedFlight(FlightTrackingData data) {
    // Generate unique notification ID from Firestore doc ID (avoid collision with service ID 900)
    final notificationId = data.firestoreId.hashCode.abs() % 90000 + 10000;

    final tf = _TrackedFlight(
      flightNumber: data.flightNumber,
      originCity: data.originCity,
      destinationCity: data.destinationCity,
      departureDateTime: data.departureDateTime,
      arrivalDateTime: data.arrivalDateTime,
      notificationId: notificationId,
      gate: data.gate,
      departureTerminal: data.departureTerminal,
      arrivalTerminal: data.arrivalTerminal,
      originAirport: data.originAirport,
      destinationAirport: data.destinationAirport,
    );
    if (data.delayMinutes != null && data.delayMinutes! > 0) {
      tf.delayMinutes = data.delayMinutes;
    }
    if (data.baggageBelt != null) {
      tf.baggageBelt = data.baggageBelt;
    }
    _trackedFlights[data.firestoreId] = tf;

    debugPrint(
        '[FlightTracking] Now tracking ${data.flightNumber} (id: ${data.firestoreId}, notifId: $notificationId)');
  }

  // ============================================================
  // ANDROID — NOTIFICATION CONTENT (existing, unchanged)
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

    await _androidChannel.invokeMethod('showFlightNotification', {
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
  // iOS — LIVE ACTIVITY MANAGEMENT
  // ============================================================

  Map<String, dynamic> _buildLiveActivityParams(String flightId) {
    final tracked = _trackedFlights[flightId];
    if (tracked == null) return {};

    final now = DateTime.now();
    final departed = tracked.departureDateTime.isBefore(now);
    final landed = tracked.arrivalDateTime != null &&
        tracked.arrivalDateTime!.isBefore(now);

    String status;
    int progress = 0;

    if (tracked.status == 'cancelled') {
      status = 'Cancelled';
    } else if (tracked.status == 'diverted') {
      status = 'Diverted';
      progress = 50;
    } else if (landed || tracked.status == 'landed') {
      status = 'Landed';
      progress = 100;
    } else if (departed || tracked.status == 'departed') {
      status = 'In Flight';
      if (tracked.arrivalDateTime != null) {
        final totalMinutes = tracked.arrivalDateTime!
            .difference(tracked.departureDateTime)
            .inMinutes;
        final elapsed = now.difference(tracked.departureDateTime).inMinutes;
        progress = totalMinutes > 0
            ? ((elapsed / totalMinutes) * 100).clamp(0, 100).toInt()
            : 50;
      }
    } else {
      status = (tracked.delayMinutes != null && tracked.delayMinutes! > 0)
          ? 'Delayed'
          : 'Scheduled';
    }

    final scheduledDeparture = tracked.departureDateTime;
    final scheduledArrival = tracked.arrivalDateTime ??
        tracked.departureDateTime.add(const Duration(hours: 2));
    final delay = tracked.delayMinutes ?? 0;
    final estimatedDeparture = delay > 0
        ? scheduledDeparture.add(Duration(minutes: delay))
        : scheduledDeparture;
    final estimatedArrival = delay > 0
        ? scheduledArrival.add(Duration(minutes: delay))
        : scheduledArrival;

    return {
      'flightId': flightId,
      'flightNumber': tracked.flightNumber,
      'originCity': tracked.originCity,
      'destinationCity': tracked.destinationCity,
      'originAirport': tracked.originAirport ?? tracked.originCity,
      'destinationAirport': tracked.destinationAirport ?? tracked.destinationCity,
      'scheduledDeparture': scheduledDeparture.millisecondsSinceEpoch.toDouble(),
      'scheduledArrival': scheduledArrival.millisecondsSinceEpoch.toDouble(),
      'status': status,
      'departureGate': tracked.gate,
      'arrivalGate': tracked.arrivalTerminal != null ? null : null,
      'departureTerminal': tracked.departureTerminal,
      'arrivalTerminal': tracked.arrivalTerminal,
      'estimatedDeparture': estimatedDeparture.millisecondsSinceEpoch.toDouble(),
      'estimatedArrival': estimatedArrival.millisecondsSinceEpoch.toDouble(),
      'delayMinutes': delay,
      'progress': progress,
      'baggageBelt': tracked.baggageBelt,
      'diversionAirport': tracked.diversionAirport,
    };
  }

  Future<void> _startOrUpdateLiveActivity(String flightId) async {
    final tracked = _trackedFlights[flightId];
    if (tracked == null) return;

    final params = _buildLiveActivityParams(flightId);
    if (params.isEmpty) return;

    if (tracked.liveActivityId != null) {
      // Already started — update
      try {
        await _iosChannel.invokeMethod('updateLiveActivity', params);
        debugPrint('[FlightTracking] iOS: Updated Live Activity for ${tracked.flightNumber}');
      } catch (e) {
        debugPrint('[FlightTracking] iOS: Failed to update Live Activity: $e');
      }
    } else {
      // Start new Live Activity
      try {
        final result = await _iosChannel.invokeMethod<Map>('startLiveActivity', params);
        if (result != null) {
          tracked.liveActivityId = result['activityId'] as String?;
          final pushToken = result['pushToken'] as String?;
          debugPrint('[FlightTracking] iOS: Started Live Activity ${tracked.liveActivityId} for ${tracked.flightNumber}');
          if (pushToken != null) {
            await _storeLiveActivityPushToken(flightId, pushToken);
          }
        }
      } catch (e) {
        debugPrint('[FlightTracking] iOS: Failed to start Live Activity: $e');
      }
    }
  }

  Future<void> _endLiveActivity(String flightId) async {
    final tracked = _trackedFlights[flightId];
    if (tracked == null || tracked.liveActivityId == null) return;

    final params = _buildLiveActivityParams(flightId);
    try {
      await _iosChannel.invokeMethod('endLiveActivity', params);
      debugPrint('[FlightTracking] iOS: Ended Live Activity for ${tracked.flightNumber}');
    } catch (e) {
      debugPrint('[FlightTracking] iOS: Failed to end Live Activity: $e');
    }
  }

  Future<void> _storeLiveActivityPushToken(String flightId, String pushToken) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('flights')
          .doc(flightId)
          .update({'liveActivityPushToken': pushToken});

      debugPrint('[FlightTracking] Stored Live Activity push token for $flightId');
    } catch (e) {
      debugPrint('[FlightTracking] Failed to store push token: $e');
    }
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

    // Re-render with updated state
    if (Platform.isAndroid) {
      _showFlightNotification(matchedId);
    } else if (Platform.isIOS) {
      _startOrUpdateLiveActivity(matchedId);
    }
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
      if (Platform.isAndroid) {
        await _androidChannel.invokeMethod('cancelFlightNotification', tracked.notificationId);
      } else if (Platform.isIOS && tracked.liveActivityId != null) {
        await _endLiveActivity(flightId);
      }
      debugPrint(
          '[FlightTracking] Stopped tracking ${tracked.flightNumber}');
    }

    if (_trackedFlights.isEmpty && Platform.isAndroid) {
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
