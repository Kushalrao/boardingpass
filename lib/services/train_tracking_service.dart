import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Data needed to start tracking a train.
class TrainTrackingData {
  final String firestoreId;
  final String trainNumber;
  final String trainName;
  final String originStation;
  final String originCode;
  final String destinationStation;
  final String destinationCode;

  TrainTrackingData({
    required this.firestoreId,
    required this.trainNumber,
    required this.trainName,
    required this.originStation,
    required this.originCode,
    required this.destinationStation,
    required this.destinationCode,
  });
}

/// Internal mutable state for a tracked train.
class _TrackedTrain {
  final TrainTrackingData data;
  String? liveActivityId;

  // Mutable state updated by polling
  String? currentStation;
  String? currentStationCode;
  String? nextStation;
  String? nextStationCode;
  String? nextStationArrival;
  String? destinationArrival;
  int delayMinutes = 0;
  int? platform;
  String status = 'not_started'; // not_started, running, arrived, completed
  String? lastUpdated;
  int progress = 0;
  int totalStations = 0;
  int passedStations = 0;

  _TrackedTrain({required this.data});
}

/// Service that polls the train scraper API and manages iOS Live Activities.
class TrainTrackingService {
  static const MethodChannel _iosChannel =
      MethodChannel('com.example.airtime/live_activity');

  static const String _scraperBaseUrl =
      'https://train-scraper-749462764377.us-central1.run.app';

  static const Duration _pollInterval = Duration(minutes: 2);

  final Map<String, _TrackedTrain> _trackedTrains = {};
  Timer? _pollingTimer;
  bool _isPolling = false;

  /// Start tracking trains and launch Live Activities.
  Future<void> startTracking(List<TrainTrackingData> trains) async {
    for (final train in trains) {
      if (_trackedTrains.containsKey(train.firestoreId)) continue;

      final tracked = _TrackedTrain(data: train);
      _trackedTrains[train.firestoreId] = tracked;

      // Do an initial poll immediately
      await _pollTrainStatus(train.firestoreId);

      // Start Live Activity on iOS
      if (Platform.isIOS) {
        await _startOrUpdateLiveActivity(train.firestoreId);
      }
    }

    // Start periodic polling if not already running
    _startPolling();
  }

  /// Stop tracking a specific train.
  Future<void> stopTracking(String trainId) async {
    if (Platform.isIOS) {
      await _endLiveActivity(trainId);
    }
    _trackedTrains.remove(trainId);

    if (_trackedTrains.isEmpty) {
      _stopPolling();
    }
  }

  /// Stop tracking all trains.
  Future<void> stopAll() async {
    for (final trainId in _trackedTrains.keys.toList()) {
      if (Platform.isIOS) {
        await _endLiveActivity(trainId);
      }
    }
    _trackedTrains.clear();
    _stopPolling();
  }

  /// Dispose the service.
  void dispose() {
    _stopPolling();
  }

  // MARK: - Polling

  void _startPolling() {
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(_pollInterval, (_) => _pollAll());
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _pollAll() async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      for (final trainId in _trackedTrains.keys.toList()) {
        await _pollTrainStatus(trainId);

        final tracked = _trackedTrains[trainId];
        if (tracked == null) continue;

        // Update Live Activity
        if (Platform.isIOS) {
          await _startOrUpdateLiveActivity(trainId);
        }

        // Auto-stop if journey completed
        if (tracked.status == 'completed') {
          // Keep showing for 10 minutes after completion
          Future.delayed(const Duration(minutes: 10), () {
            stopTracking(trainId);
          });
        }
      }
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _pollTrainStatus(String trainId) async {
    final tracked = _trackedTrains[trainId];
    if (tracked == null) return;

    try {
      final url = '$_scraperBaseUrl/live/${tracked.data.trainNumber}';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != 200) {
        print('[TrainTracking] HTTP ${response.statusCode} for ${tracked.data.trainNumber}');
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        print('[TrainTracking] API returned success=false for ${tracked.data.trainNumber}');
        return;
      }

      _updateTrackedTrain(trainId, data);
    } catch (e) {
      print('[TrainTracking] Poll failed for ${tracked.data.trainNumber}: $e');
    }
  }

  void _updateTrackedTrain(String trainId, Map<String, dynamic> data) {
    final tracked = _trackedTrains[trainId];
    if (tracked == null) return;

    final stations = data['stations'] as List<dynamic>? ?? [];
    if (stations.isEmpty) return;

    tracked.totalStations = stations.length;
    tracked.lastUpdated = data['lastUpdated'] as String?;

    // Get destination arrival time from last station
    final lastStation = stations.last as Map<String, dynamic>;
    tracked.destinationArrival = lastStation['scheduledArrival'] as String?;

    // Find current station (status == "arrived") and next station
    String? currentStation;
    String? currentStationCode;
    String? nextStation;
    String? nextStationCode;
    String? nextStationArrival;
    int lastDepartedIndex = -1;
    int currentDelay = 0;
    int? currentPlatform;
    bool allDeparted = true;
    bool anyDeparted = false;

    for (int i = 0; i < stations.length; i++) {
      final s = stations[i] as Map<String, dynamic>;
      final stationStatus = s['status'] as String? ?? 'upcoming';

      if (stationStatus == 'arrived') {
        // Train is currently at this station
        currentStation = s['name'] as String?;
        currentStationCode = s['code'] as String?;
        currentDelay = s['delay'] as int? ?? 0;
        currentPlatform = s['platform'] as int?;
        lastDepartedIndex = i;
        anyDeparted = true;

        // Next station is i+1
        if (i + 1 < stations.length) {
          final next = stations[i + 1] as Map<String, dynamic>;
          nextStation = next['name'] as String?;
          nextStationCode = next['code'] as String?;
          nextStationArrival = next['scheduledArrival'] as String?;
        }
        allDeparted = false;
        break;
      } else if (stationStatus == 'departed') {
        lastDepartedIndex = i;
        currentDelay = s['delay'] as int? ?? currentDelay;
        anyDeparted = true;
      } else {
        allDeparted = false;
        if (anyDeparted && nextStation == null) {
          // First upcoming station after departed ones = next station
          nextStation = s['name'] as String?;
          nextStationCode = s['code'] as String?;
          nextStationArrival = s['scheduledArrival'] as String?;
          currentPlatform = s['platform'] as int?;
        }
      }
    }

    // If no "arrived" station, use the last departed one as current
    if (currentStation == null && lastDepartedIndex >= 0) {
      final lastDep = stations[lastDepartedIndex] as Map<String, dynamic>;
      currentStation = lastDep['name'] as String?;
      currentStationCode = lastDep['code'] as String?;
    }

    // Determine overall status
    if (!anyDeparted) {
      tracked.status = 'not_started';
    } else if (allDeparted && lastDepartedIndex == stations.length - 1) {
      tracked.status = 'completed';
    } else {
      tracked.status = 'running';
    }

    tracked.currentStation = currentStation;
    tracked.currentStationCode = currentStationCode;
    tracked.nextStation = nextStation;
    tracked.nextStationCode = nextStationCode;
    tracked.nextStationArrival = nextStationArrival;
    tracked.delayMinutes = currentDelay;
    tracked.platform = currentPlatform;

    // Calculate progress
    if (tracked.totalStations > 1) {
      tracked.passedStations = lastDepartedIndex + 1;
      tracked.progress =
          ((tracked.passedStations / tracked.totalStations) * 100).round();
    }

    print('[TrainTracking] ${tracked.data.trainNumber}: '
        'status=${tracked.status}, '
        'current=$currentStation, '
        'next=$nextStation, '
        'delay=${tracked.delayMinutes}m, '
        'progress=${tracked.progress}%');
  }

  // MARK: - iOS Live Activity

  Map<String, dynamic> _buildLiveActivityParams(String trainId) {
    final tracked = _trackedTrains[trainId]!;
    return {
      'trainId': trainId,
      'trainNumber': tracked.data.trainNumber,
      'trainName': tracked.data.trainName,
      'originStation': tracked.data.originStation,
      'originCode': tracked.data.originCode,
      'destinationStation': tracked.data.destinationStation,
      'destinationCode': tracked.data.destinationCode,
      'currentStation': tracked.currentStation,
      'currentStationCode': tracked.currentStationCode,
      'nextStation': tracked.nextStation,
      'nextStationCode': tracked.nextStationCode,
      'nextStationArrival': tracked.nextStationArrival,
      'destinationArrival': tracked.destinationArrival,
      'delayMinutes': tracked.delayMinutes,
      'platform': tracked.platform,
      'status': tracked.status,
      'lastUpdated': tracked.lastUpdated,
      'progress': tracked.progress,
    };
  }

  Future<void> _startOrUpdateLiveActivity(String trainId) async {
    final tracked = _trackedTrains[trainId];
    if (tracked == null) return;

    final params = _buildLiveActivityParams(trainId);

    try {
      if (tracked.liveActivityId != null) {
        // Update existing activity
        await _iosChannel.invokeMethod('updateTrainLiveActivity', params);
      } else {
        // Start new activity
        final result = await _iosChannel.invokeMethod<Map<dynamic, dynamic>>(
          'startTrainLiveActivity',
          params,
        );
        if (result != null) {
          tracked.liveActivityId = result['activityId'] as String?;
          print('[TrainTracking] Live Activity started: ${tracked.liveActivityId}');
        }
      }
    } catch (e) {
      print('[TrainTracking] Live Activity error: $e');
    }
  }

  Future<void> _endLiveActivity(String trainId) async {
    final tracked = _trackedTrains[trainId];
    if (tracked?.liveActivityId == null) return;

    try {
      final params = _buildLiveActivityParams(trainId);
      await _iosChannel.invokeMethod('endTrainLiveActivity', params);
      print('[TrainTracking] Live Activity ended for $trainId');
    } catch (e) {
      print('[TrainTracking] Failed to end Live Activity: $e');
    }
  }
}
