import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:chating/firebase_options.dart';
import 'package:chating/screens/login_screen.dart';
import 'package:chating/screens/home_screen.dart';
import 'package:chating/screens/admin_screen.dart';
import 'package:chating/screens/gender_selection_screen.dart';
import 'package:chating/screens/profile_setup_screen.dart';
import 'package:chating/services/auth_service.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/services/notification_service.dart';
import 'package:chating/services/permission_service.dart';
import 'package:chating/screens/permission_screen.dart';
import 'package:chating/models/app_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:chating/services/zego_service.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:chating/services/zim_service.dart';
import 'package:chating/services/callkit_service.dart';
import 'package:chating/screens/chat_screen.dart';

/// ── Background FCM Message Handler ──────────────────────────────────────────
/// MUST be a top-level function (not inside a class) and annotated with
/// @pragma('vm:entry-point') so the Dart VM keeps it alive when app is killed.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be initialized before any Firebase call in background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('📩 BG FCM message: ${message.data}');

  final data = message.data;

  // Distinguish between Zego Calls and ZIM Messages
  bool isCall = false;
  if (data.containsKey('call_id')) {
    isCall = true;
  } else if (data.containsKey('zego')) {
    try {
      final zegoData = jsonDecode(data['zego'] as String);
      if (zegoData.containsKey('call_id') ||
          zegoData.containsKey('invitation_id') ||
          zegoData.containsKey('call_type') ||
          zegoData.containsKey('type')) {
        isCall = true;
      }
    } catch (_) {}
  }

  if (isCall) {
    print('📞 Zego Call detected in background. Intercepting for CallKit...');
    try {
      String callId = data['call_id'] ?? '';
      String callerName = data['caller_name'] ?? 'Incoming Call';
      String? callerPhoto = data['caller_photo'] ?? data['avatar'];
      bool isVideo = data['call_type'] == 'video' ||
          data['is_video'] == 'true' ||
          data['type'] == '1';

      if (data.containsKey('zego')) {
        final zegoData = jsonDecode(data['zego'] as String);
        callId = zegoData['call_id'] ?? zegoData['invitation_id'] ?? callId;
        callerName =
            zegoData['caller_name'] ?? zegoData['inviter_name'] ?? callerName;
        callerPhoto =
            zegoData['caller_photo'] ?? zegoData['avatar'] ?? callerPhoto;
        isVideo = zegoData['call_type'] == 'video' ||
            zegoData['is_video'] == 'true' ||
            zegoData['type'] == 1 ||
            isVideo;
      }

      if (callId.isEmpty) {
        callId = DateTime.now().millisecondsSinceEpoch.toString();
      }

      await CallKitService.showCallkitIncoming(
        callId: callId,
        callerName: callerName,
        callerPhoto: callerPhoto,
        isVideo: isVideo,
      );
    } catch (e) {
      print('❌ Error parsing Zego background notification: $e');
    }
    return;
  }

  String? senderId = data['sender_id'];
  String? parsedSenderName;

  if (data.containsKey('payload')) {
    try {
      final payloadData = jsonDecode(data['payload'] as String);
      senderId = payloadData['sender_id'] ?? senderId;
      parsedSenderName = payloadData['sender_name'];
    } catch (_) {}
  }

  String finalSenderName = parsedSenderName ?? data['sender_name'] ?? data['title'] ?? 'New Message';
  String title = message.notification?.title ?? finalSenderName;
  String body =
      message.notification?.body ?? data['content'] ?? data['body'] ?? '';

  // Show local notification for CHAT MESSAGES only
  final notificationPayload = jsonEncode({
    'click_action': 'open_chat',
    'sender_id': senderId ?? '',
    'sender_name': finalSenderName,
  });

  await NotificationService().showNotification(
    title: title,
    body: body,
    payload: notificationPayload,
    isCall: false,
  );
}

late SharedPreferences prefs;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    prefs = await SharedPreferences.getInstance();
    print('🚀 Starting Firebase initialization...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized');

    // ✅ Register background FCM handler BEFORE runApp
    print('🚀 Registering FCM background handler...');
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // ✅ Initialize NotificationService (FCM token + ZPNs registration)
    print('🚀 Initializing NotificationService...');
    await NotificationService().init().timeout(const Duration(seconds: 10),
        onTimeout: () {
      print('⚠️ NotificationService init timed out');
    });
    print('✅ NotificationService ready');

    // We no longer block main() with Zego/Zim init.
    _initBackgroundServices();
  } catch (e) {
    print('❌ Critical Initialization Error: $e');
  }

  runApp(const MyApp());
}

/// Runs non-critical initializations in the background
Future<void> _initBackgroundServices() async {
  try {
    print('🚀 Starting background service initialization...');
    // Only get the ALREADY LOGGED IN user
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      print('✅ Existing user found: ${user.uid}');

      final spoofedUid = prefs.getString('spoofed_uid');
      AppUser appUser;
      if (spoofedUid != null && spoofedUid.isNotEmpty) {
        appUser = AppUser(
            uid: spoofedUid,
            displayName: 'User',
            email: 'admin_seed@example.com',
            isSeed: true);
      } else {
        appUser = AppUser.fromFirebaseUser(user);
      }

      final profile = await UserService.getUserData(appUser)
          .timeout(const Duration(seconds: 5));
      final displayName = profile?['name'] ?? user.displayName ?? 'User';
      print('👤 Display name: $displayName');

      print('🚀 Initializing Zego and Zim...');
      await ZegoService().init(userID: appUser.uid, userName: displayName);
      await ZimService().init(userID: appUser.uid, userName: displayName);
      print('✅ Zego and Zim initialized');
    } else {
      print('⚠️ No user logged in yet. Waiting for login.');
    }
  } catch (e) {
    print('⚠️ Background Service Init Error: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final navigatorKey = GlobalKey<NavigatorState>();

  // ✅ Cache the future and user so they are NOT recreated on every rebuild
  Future<Map<String, dynamic>?>? _profileFuture;
  String? _cachedUserId;

  @override
  void initState() {
    super.initState();
    ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);

    // Initialize CallKit/ConnectionService event listeners
    CallKitService.listenToEvents(
      onAccept: (callId, isVideo) async {
        print('🚀 CallKit accepted call: $callId');
        try {
          FlutterRingtonePlayer().stop();
        } catch (_) {}
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          final appUser = AppUser.fromFirebaseUser(currentUser);
          final profile = await UserService.getUserData(appUser);
          final displayName =
              profile?['name'] ?? currentUser.displayName ?? 'User';

          await ZegoService().init(userID: appUser.uid, userName: displayName);

          // Wait slightly for ZIM to sync the invitation state
          await Future.delayed(const Duration(seconds: 1));
          await ZegoUIKitPrebuiltCallInvitationService().accept();
        }
      },
      onDecline: (callId) async {
        print('🚀 CallKit declined call: $callId');
        try {
          FlutterRingtonePlayer().stop();
        } catch (_) {}
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          final appUser = AppUser.fromFirebaseUser(currentUser);
          final profile = await UserService.getUserData(appUser);
          final displayName =
              profile?['name'] ?? currentUser.displayName ?? 'User';

          await ZegoService().init(userID: appUser.uid, userName: displayName);

          // Wait slightly for ZIM to sync the invitation state
          await Future.delayed(const Duration(seconds: 1));
          await ZegoUIKitPrebuiltCallInvitationService().reject();
           final state = WidgetsBinding.instance.lifecycleState;
          final isAppInBackgroundOrKilled =
              state == AppLifecycleState.paused || state == AppLifecycleState.detached;
          if (isAppInBackgroundOrKilled) {
            print('Device is in background/killed state ($state) - uninitializing ZegoService.');
            ZegoService().uninit();
          } else {
            print('App is visible/foreground ($state) - keeping ZegoService initialized.');
          }
        }
      },
    );

    NotificationService().onChatNotificationTapped = (senderId, senderName) {
      _navigateToChat(senderId);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (NotificationService().pendingAction == 'accept') {
        print('🚀 App started via "Receive" button. Ensuring Zego is ready...');
        await Future.delayed(const Duration(seconds: 1));
        NotificationService().clearPendingAction();
      }

      final pendingChatSenderId = NotificationService().pendingChatSenderId;
      if (pendingChatSenderId != null && pendingChatSenderId.isNotEmpty) {
        print('🚀 App started via chat notification. Navigating to chat...');
        _navigateToChat(pendingChatSenderId);
        NotificationService().clearPendingChatSenderId();
      }
    });
  }

  Future<void> _navigateToChat(String senderId) async {
    print('🚀 Navigating to chat with $senderId');
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('⚠️ No logged in user. Cannot navigate to chat.');
      return;
    }

    final appUser = AppUser.fromFirebaseUser(currentUser);
    final targetProfileUser = AppUser(uid: senderId, displayName: '', email: '');
    final targetProfile = await UserService.getUserData(targetProfileUser);
    if (targetProfile == null) {
      print('⚠️ Sender profile not found.');
      return;
    }

    Future<void> onCallUser(Map<String, dynamic> profile, {required bool isVideoCall}) async {
      final targetUid = profile['uid']?.toString() ?? '';
      if (targetUid.isEmpty) return;

      final isSeed = profile['isSeed'] == true || profile['isSeed'] == 'true';
      List<ZegoCallUser> invitees = [];
      if (isSeed && profile['adminUid'] != null && profile['adminUid'].toString().isNotEmpty) {
        final adminId = profile['adminUid'].toString();
        invitees = [ZegoCallUser(adminId, profile['name'] ?? 'Admin')];
      } else {
        invitees = [ZegoCallUser(targetUid, profile['name'] ?? 'User')];
      }

      if (invitees.isEmpty || invitees.first.id.isEmpty) return;

      final currentUserProfile = await UserService.getUserData(appUser);
      final currentUserName = currentUserProfile?['name'] as String? ?? appUser.displayName;

      final alertId = await UserService.saveCallAlert(
        targetUid: invitees.first.id,
        callerId: appUser.uid,
        callerName: currentUserName,
        callerPhoto: appUser.photoURL,
        isVideo: isVideoCall,
        status: 'missed',
      );

      final result = await ZegoUIKitPrebuiltCallInvitationService().send(
        invitees: invitees,
        isVideoCall: isVideoCall,
        resourceID: 'zego_call',
        timeoutSeconds: 60,
      );

      if (!result && alertId != null) {
        await UserService.updateCallAlertStatus(
          invitees.first.id,
          alertId,
          'offline',
        );
      }
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          currentUser: appUser,
          targetProfile: targetProfile,
          onCallUser: onCallUser,
        ),
      ),
    );
  }

  /// Returns a cached profile future. Only re-fetches if the user changes.
  Future<Map<String, dynamic>?> _getProfileFuture(AppUser user) {
    if (_cachedUserId != user.uid || _profileFuture == null) {
      _cachedUserId = user.uid;
      _profileFuture = UserService.getUserData(user);
    }
    return _profileFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZegoChat',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
      ),
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            ZegoUIKitPrebuiltCallMiniOverlayPage(
              contextQuery: () {
                final context = navigatorKey.currentState?.context;
                return context ?? navigatorKey.currentContext!;
              },
            ),
          ],
        );
      },
      home: StreamBuilder<User?>(
        stream: AuthService().authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorScreen(message: 'Auth Error: ${snapshot.error}');
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return const LoginScreen();
          }

          final user = snapshot.data!;

          if (user.email == 'analystcodehub@gmail.com') {
            return const AdminScreen();
          }

          final spoofedUid = prefs.getString('spoofed_uid');
          AppUser appUser;
          if (spoofedUid != null && spoofedUid.isNotEmpty) {
            appUser = AppUser(
                uid: spoofedUid,
                displayName: 'User',
                email: 'admin_seed@example.com',
                isSeed: true);
          } else {
            appUser = AppUser.fromFirebaseUser(user);
          }

          return FutureBuilder<bool>(
            future: PermissionService.checkAllPermissions(),
            builder: (context, permSnap) {
              if (permSnap.connectionState == ConnectionState.waiting) {
                return const SplashScreen();
              }

              final permissionsGranted = permSnap.data ?? false;

              if (!permissionsGranted) {
                return PermissionScreen(
                  onGranted: () {
                    setState(() {});
                  },
                );
              }

              return FutureBuilder<Map<String, dynamic>?>(
                // ✅ Use cached future — prevents grey screen on app reopen
                future: _getProfileFuture(appUser),
                builder: (context, profileSnap) {
                  if (profileSnap.hasError) {
                    return ErrorScreen(
                      message:
                          'Database Error: ${profileSnap.error}\n\nCheck your internet connection or database rules.',
                      onRetry: () {
                        // Clear cache and retry
                        setState(() {
                          _cachedUserId = null;
                          _profileFuture = null;
                        });
                      },
                    );
                  }

                  if (profileSnap.connectionState == ConnectionState.waiting) {
                    return const SplashScreen();
                  }

                  final profile = profileSnap.data;
                  final gender = profile?['gender'] as String?;
                  final phone = profile?['phone'] as String?;
                  final lookingFor = profile?['lookingFor'] as String?;

                  if (gender == null || gender.isEmpty) {
                    return GenderSelectionScreen(user: appUser);
                  }

                  if (phone == null || phone.isEmpty) {
                    return ProfileSetupScreen(
                        user: appUser, initialGender: gender);
                  }

                  return HomeScreen(
                    user: appUser,
                    myGender: gender,
                    lookingFor: lookingFor,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorScreen({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 80),
              const SizedBox(height: 24),
              const Text(
                'Oops! Something went wrong',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 32),
              if (onRetry != null)
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.video_call_rounded,
                  size: 80, color: Color(0xFF6C63FF)),
              SizedBox(height: 20),
              CircularProgressIndicator(color: Color(0xFF6C63FF)),
            ],
          ),
        ),
      ),
    );
  }
}
