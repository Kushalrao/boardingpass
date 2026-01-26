import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[NotificationService] Background message: ${message.messageId}');
  // Handle background message if needed
}

/// Notification Service for handling FCM push notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _fcmToken;
  String? _userId;

  /// Get current FCM token
  String? get fcmToken => _fcmToken;

  /// Initialize the notification service
  Future<void> init(String userId) async {
    _userId = userId;
    debugPrint('[NotificationService] Initializing for user: $userId');

    // Request permission
    await _requestPermission();

    // Initialize local notifications for foreground display
    await _initLocalNotifications();

    // Get and store FCM token
    await _getAndStoreToken();

    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_onTokenRefresh);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // Check if app was opened from a notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _onMessageOpenedApp(initialMessage);
    }

    debugPrint('[NotificationService] Initialization complete');
  }

  /// Request notification permission
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: true,
      criticalAlert: false,
    );

    debugPrint(
        '[NotificationService] Permission status: ${settings.authorizationStatus}');
  }

  /// Initialize local notifications for foreground display
  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create Android notification channel
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'flight_status',
        'Flight Status',
        description: 'Notifications for flight status updates',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Get FCM token and store in Firestore
  Future<void> _getAndStoreToken() async {
    try {
      // For iOS, get APNS token first
      if (Platform.isIOS) {
        final apnsToken = await _messaging.getAPNSToken();
        debugPrint('[NotificationService] APNS token: $apnsToken');
      }

      _fcmToken = await _messaging.getToken();
      debugPrint('[NotificationService] FCM token: $_fcmToken');

      if (_fcmToken != null && _userId != null) {
        await _storeToken(_fcmToken!);
      }
    } catch (e) {
      debugPrint('[NotificationService] Error getting FCM token: $e');
    }
  }

  /// Store FCM token in Firestore
  Future<void> _storeToken(String token) async {
    if (_userId == null) return;

    try {
      await _firestore.collection('users').doc(_userId).update({
        'fcmTokens': FieldValue.arrayUnion([
          {
            'token': token,
            'platform': Platform.isIOS ? 'ios' : 'android',
            'createdAt': DateTime.now().toIso8601String(),
          }
        ]),
      });
      debugPrint('[NotificationService] Token stored in Firestore');
    } catch (e) {
      debugPrint('[NotificationService] Error storing token: $e');
    }
  }

  /// Handle token refresh
  Future<void> _onTokenRefresh(String newToken) async {
    debugPrint('[NotificationService] Token refreshed: $newToken');

    // Remove old token and add new one
    if (_fcmToken != null && _userId != null) {
      try {
        await _firestore.collection('users').doc(_userId).update({
          'fcmTokens': FieldValue.arrayRemove([
            {'token': _fcmToken}
          ]),
        });
      } catch (e) {
        debugPrint('[NotificationService] Error removing old token: $e');
      }
    }

    _fcmToken = newToken;
    await _storeToken(newToken);
  }

  /// Handle foreground message - show local notification
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('[NotificationService] Foreground message: ${message.messageId}');
    debugPrint('[NotificationService] Title: ${message.notification?.title}');
    debugPrint('[NotificationService] Body: ${message.notification?.body}');
    debugPrint('[NotificationService] Data: ${message.data}');

    // Show local notification
    final notification = message.notification;
    if (notification != null) {
      await _showLocalNotification(
        title: notification.title ?? 'Flight Update',
        body: notification.body ?? '',
        payload: message.data.toString(),
      );
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'flight_status',
      'Flight Status',
      channelDescription: 'Notifications for flight status updates',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Handle notification tap when app is in background
  void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('[NotificationService] Message opened app: ${message.messageId}');
    debugPrint('[NotificationService] Data: ${message.data}');
    // TODO: Navigate to specific flight details based on message data
  }

  /// Handle local notification tap
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('[NotificationService] Notification tapped: ${response.payload}');
    // TODO: Navigate to specific flight details based on payload
  }

  /// Cleanup - remove token on sign out
  Future<void> cleanup() async {
    if (_fcmToken != null && _userId != null) {
      try {
        // Remove token from Firestore
        final userDoc = await _firestore.collection('users').doc(_userId).get();
        final tokens = userDoc.data()?['fcmTokens'] as List<dynamic>? ?? [];

        final tokenToRemove = tokens.firstWhere(
          (t) => t['token'] == _fcmToken,
          orElse: () => null,
        );

        if (tokenToRemove != null) {
          await _firestore.collection('users').doc(_userId).update({
            'fcmTokens': FieldValue.arrayRemove([tokenToRemove]),
          });
        }

        debugPrint('[NotificationService] Token removed from Firestore');
      } catch (e) {
        debugPrint('[NotificationService] Error removing token: $e');
      }
    }

    _fcmToken = null;
    _userId = null;
  }
}
