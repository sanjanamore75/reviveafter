import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:zego_zpns/zego_zpns.dart';
import 'package:chating/services/user_service.dart';

/// Manages FCM token retrieval, ZIM push registration,
/// ZPNs registration, and notification permission requests.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  String? _pendingAction;
  String? get pendingAction => _pendingAction;
  void clearPendingAction() => _pendingAction = null;

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> init() async {
    // 1. Request notification permission
    await _requestPermission();

    // 2. Initialize local notifications (for background messages)
    await _initLocalNotifications();

    // 3. Get FCM token
    _fcmToken = await _fcm.getToken();
    print('📲 NotificationService: FCM Token: $_fcmToken');

    // 4. Sync token with Firebase if logged in
    _syncToken();

    // 5. Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) {
      _fcmToken = newToken;
      print('📲 NotificationService: FCM Token refreshed: $newToken');
      _registerTokenWithZPNs(newToken);
      _syncToken();
    });

    // 6. Register with ZPNs (for offline call notifications)
    if (_fcmToken != null) {
      _registerTokenWithZPNs(_fcmToken!);
    }

    // 7. Register ZPNs push
    try {
      await ZPNs.getInstance().registerPush();
      print('✅ NotificationService: ZPNs push registered');
    } catch (e) {
      print('⚠️ NotificationService: ZPNs registration error: $e');
    }

    // 8. Handle foreground FCM messages (app is open)
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 9. Handle notification tap when app was in background (not killed)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // 10. Check for initial message (app launched from notification tap)
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _handleNotificationTap(initial);
    }

    // 11. Check for notification action launch
    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _pendingAction = launchDetails?.notificationResponse?.actionId;
      print('🚀 App launched from notification action: $_pendingAction');
    }
  }

  void _syncToken() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _fcmToken != null) {
      UserService.updateUserToken(user.uid, _fcmToken!);
    }
  }

  // ── Local Notifications Setup ──────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Handle tap on local notification or button actions
        final actionId = response.actionId;
        final payload = response.payload;
        print(
            '👆 Local notification interaction: Action=$actionId, Payload=$payload');

        if (actionId == 'accept') {
          _pendingAction = 'accept';
          print('✅ Call accepted from notification interaction');
        } else if (actionId == 'decline') {
          print('❌ Call declined from notification interaction');
        }
      },
    );

    // Create high importance channel for Android
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'call_notifications',
        'Call & Message Notifications',
        description: 'Notifications for incoming calls and messages',
        importance: Importance.max,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    print(
        '🔔 NotificationService: Notification permission: ${settings.authorizationStatus}');
  }

  // ── ZPNs Token Registration ─────────────────────────────────────────────────

  void _registerTokenWithZPNs(String token) {
    print('✅ NotificationService: Syncing token with ZPNs...');
    ZPNsConfig config = ZPNsConfig();
    ZPNs.setPushConfig(config);
  }

  // ── Foreground Message Handler ─────────────────────────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    print(
        '📩 NotificationService: FCM foreground message: ${message.notification?.title}');
  }

  // ── Notification Tap Handler ────────────────────────────────────────────────

  void _handleNotificationTap(RemoteMessage message) {
    print('👆 NotificationService: FCM Notification tapped: ${message.data}');
  }

  // ── Show Notification ──────────────────────────────────────────────────────

  /// Shows a local notification. Useful for background handlers.
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    bool isCall = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'call_notifications',
      'Call & Message Notifications',
      channelDescription: 'Notifications for incoming calls and messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      // Add buttons for calls
      actions: isCall
          ? <AndroidNotificationAction>[
              const AndroidNotificationAction(
                'accept',
                'Receive',
                showsUserInterface: true,
                cancelNotification: true,
              ),
              const AndroidNotificationAction(
                'decline',
                'Decline',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ]
          : null,
      fullScreenIntent: isCall,
      category: isCall
          ? AndroidNotificationCategory.call
          : AndroidNotificationCategory.message,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecond,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  bool get isAndroid => Platform.isAndroid;
}
