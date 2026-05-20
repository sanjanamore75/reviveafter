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
import 'package:chating/screens/spoof_login_screen.dart';
import 'package:chating/models/app_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:chating/services/zego_service.dart';
import 'package:chating/services/zim_service.dart';

/// ── Background FCM Message Handler ──────────────────────────────────────────
/// MUST be a top-level function (not inside a class) and annotated with
/// @pragma('vm:entry-point') so the Dart VM keeps it alive when app is killed.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be initialized before any Firebase call in background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('📩 BG FCM message: ${message.data}');

  // Detect if this is a call invitation
  final data = message.data;

  // Zego/ZIM often put the sender name in different fields depending on the plugin
  String? senderName =
      data['caller_name'] ?? data['sender_name'] ?? data['title'];

  bool isCall = data.containsKey('call_id') ||
      data.containsKey('zego') ||
      (message.notification?.title?.toLowerCase().contains('call') ?? false) ||
      (data['title']?.toLowerCase().contains('call') ?? false);

  String title = message.notification?.title ??
      senderName ??
      (isCall ? 'Incoming Call' : 'New Message');

  String body = message.notification?.body ??
      data['content'] ??
      data['body'] ??
      (isCall ? 'Tap to answer' : '');

  // Show local notification with buttons if it's a call
  await NotificationService().showNotification(
    title: title,
    body: body,
    payload: data.toString(),
    isCall: isCall,
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
        appUser = AppUser(uid: spoofedUid, displayName: 'User', email: 'admin_seed@example.com', isSeed: true);
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (NotificationService().pendingAction == 'accept') {
        print('🚀 App started via "Receive" button. Ensuring Zego is ready...');
        await Future.delayed(const Duration(seconds: 1));
        NotificationService().clearPendingAction();
      }
    });
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

          if (user.email == 'chatzego@gmail.com') {
            return const SpoofLoginScreen();
          }

          final spoofedUid = prefs.getString('spoofed_uid');
          AppUser appUser;
          if (spoofedUid != null && spoofedUid.isNotEmpty) {
            appUser = AppUser(uid: spoofedUid, displayName: 'User', email: 'admin_seed@example.com', isSeed: true);
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
                    return ProfileSetupScreen(user: appUser, initialGender: gender);
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
