import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:zego_zpns/zego_zpns.dart';
import 'package:chating/config/zego_config.dart';

class ZegoService {
  static final ZegoService _instance = ZegoService._internal();
  factory ZegoService() => _instance;
  ZegoService._internal();

  bool _isInitialized = false;
  String? _currentUserID;

  Future<void> init({
    required String userID,
    required String userName,
  }) async {
    // ✅ Skip re-initialization if already initialized for the same user.
    // This prevents destroying the signaling connection on every screen rebuild.
    if (_isInitialized && _currentUserID == userID) {
      print('✅ ZegoService already initialized for $userID — skipping.');
      return;
    }

    // Only uninit if switching to a DIFFERENT user
    if (_isInitialized && _currentUserID != userID) {
      print('🔄 ZegoService: switching user, uniniting for $_currentUserID');
      await ZegoUIKitPrebuiltCallInvitationService().uninit();
      _isInitialized = false;
      _currentUserID = null;
    }

    try {
      print('🚀 ZegoService: initializing for $userID...');
      // 1. Initialize Zego Invitation Service
      await ZegoUIKitPrebuiltCallInvitationService().init(
        appID: ZegoConfig.appID,
        appSign: ZegoConfig.appSign,
        userID: userID,
        userName: userName,
        plugins: [ZegoUIKitSignalingPlugin()],
        notificationConfig: ZegoCallInvitationNotificationConfig(
          androidNotificationConfig: ZegoCallAndroidNotificationConfig(
            channelID: "ZegoUIKit",
            channelName: "Call Notifications",
            icon: "default",
            showOnFullScreen: true,
          ),
          iOSNotificationConfig: ZegoCallIOSNotificationConfig(
            systemCallingIconName: 'CallKitIcon',
          ),
        ),
      );

      // 2. Register for Offline Push (Crucial for killed state)
      print('🔔 ZegoService: Registering for ZPNs offline push...');
      await ZPNs.getInstance().registerPush();

      _isInitialized = true;
      _currentUserID = userID;
      print('✅ ZegoService Initialized for $userID');
    } catch (e) {
      _isInitialized = false;
      _currentUserID = null;
      print('❌ ZegoService Initialization Failed for $userID: $e');
    }
  }

  void uninit() {
    ZegoUIKitPrebuiltCallInvitationService().uninit();
    _isInitialized = false;
    _currentUserID = null;
    print('❌ ZegoService Uninitialized');
  }
}
