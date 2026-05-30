import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:zego_zpns/zego_zpns.dart';
import 'package:chating/config/zego_config.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:chating/services/callkit_service.dart';

class ZegoService {
  static final ZegoService _instance = ZegoService._internal();
  factory ZegoService() => _instance;
  ZegoService._internal();

  String? _currentUserID;

  Future<void> init({
    required String userID,
    required String userName,
  }) async {
    final bool zegoInitState = ZegoUIKitPrebuiltCallInvitationService().isInit;

    // ✅ Skip re-initialization if already initialized for the same user.
    // This prevents destroying the signaling connection on every screen rebuild.
    if (zegoInitState && _currentUserID == userID) {
      print('✅ ZegoService already initialized for $userID — skipping.');
      return;
    }

    // Only uninit if switching to a DIFFERENT user
    if (zegoInitState && _currentUserID != userID) {
      print('🔄 ZegoService: switching user, uniniting for $_currentUserID');
      await ZegoUIKitPrebuiltCallInvitationService().uninit();
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
            channelID: "ZegoDefaultSystemRingtoneChannel",
            channelName: "Call Notifications",
            icon: "default",
            vibrate: true,
            showOnFullScreen: true,
          ),
          iOSNotificationConfig: ZegoCallIOSNotificationConfig(
            systemCallingIconName: 'CallKitIcon',
          ),
        ),
        invitationEvents: ZegoUIKitPrebuiltCallInvitationEvents(
          onIncomingCallReceived: (callID, caller, callType, callees, customData) {
            print('🔔 ZegoService: Foreground call received. Playing system ringtone.');
            try {
              FlutterRingtonePlayer().playRingtone(asAlarm: false, looping: true);
            } catch (e) {
              print('⚠️ ZegoService error playing system ringtone: $e');
            }

            if (CallKitService.acceptingCallId != null) {
              print('🚀 ZegoService: Call already accepted via CallKit. Direct accept triggered.');
              ZegoUIKitPrebuiltCallInvitationService().accept();
              CallKitService.acceptingCallId = null;
            } else if (CallKitService.decliningCallId != null) {
              print('🚀 ZegoService: Call already declined via CallKit. Direct reject triggered.');
              ZegoUIKitPrebuiltCallInvitationService().reject();
              CallKitService.decliningCallId = null;
            }
          },
          onIncomingCallAcceptButtonPressed: () {
            print('🔕 ZegoService: Accept button pressed. Stopping system ringtone.');
            try {
              FlutterRingtonePlayer().stop();
            } catch (e) {
              print('⚠️ ZegoService error stopping system ringtone: $e');
            }
          },
          onIncomingCallDeclineButtonPressed: () {
            print('🔕 ZegoService: Decline button pressed. Stopping system ringtone.');
            try {
              FlutterRingtonePlayer().stop();
            } catch (e) {
              print('⚠️ ZegoService error stopping system ringtone: $e');
            }
          },
          onIncomingCallCanceled: (callID, caller, customData) {
            print('🔕 ZegoService: Call canceled by caller. Stopping system ringtone.');
            try {
              FlutterRingtonePlayer().stop();
            } catch (e) {
              print('⚠️ ZegoService error stopping system ringtone: $e');
            }
          },
          onIncomingCallTimeout: (callID, caller) {
            print('🔕 ZegoService: Call timed out. Stopping system ringtone.');
            try {
              FlutterRingtonePlayer().stop();
            } catch (e) {
              print('⚠️ ZegoService error stopping system ringtone: $e');
            }
          },
        ),
      );

      // 2. Register for Offline Push (Crucial for killed state)
      print('🔔 ZegoService: Registering for ZPNs offline push...');
      await ZPNs.getInstance().registerPush();

      _currentUserID = userID;
      print('✅ ZegoService Initialized for $userID');
    } catch (e) {
      _currentUserID = null;
      print('❌ ZegoService Initialization Failed for $userID: $e');
    }
  }

  void uninit() {
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
    ZegoUIKitPrebuiltCallInvitationService().uninit();
    _currentUserID = null;
    print('❌ ZegoService Uninitialized');
  }

  bool get isInitialized => ZegoUIKitPrebuiltCallInvitationService().isInit;
}
