import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallKitService {
  static String? acceptingCallId;
  static String? decliningCallId;

  /// Shows the native incoming call UI (ConnectionService on Android / CallKit on iOS)
  static Future<void> showCallkitIncoming({
    required String callId,
    required String callerName,
    required String? callerPhoto,
    required bool isVideo,
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'ZegoChat',
      avatar: (callerPhoto != null && callerPhoto.isNotEmpty) ? callerPhoto : 'https://placeholder.com/avatar.png',
      handle: isVideo ? 'Video Call' : 'Voice Call',
      type: isVideo ? 1 : 0,
      duration: 30000,
      android: const AndroidParams(
        isCustomNotification: false,
        isShowLogo: true,
        ringtonePath: 'incoming',
        backgroundColor: '#1a1a2e',
        incomingCallNotificationChannelName: 'Incoming Calls',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitIcon',
        handleType: 'generic',
        supportsVideo: true,
      ),
    );

    print('🔔 CallKitService: Showing incoming call UI for $callerName (ID: $callId)');
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Listens to CallKit events and coordinates with the Zego Prebuilt Call UI.
  static void listenToEvents({
    required Function(String callId, bool isVideo) onAccept,
    required Function(String callId) onDecline,
  }) {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      print('📞 CallKitEvent: ${event.event} - ${event.body}');

      switch (event.event) {
        case Event.actionCallAccept:
          final callId = event.body['id'] as String;
          final isVideo = event.body['type'] == 1;
          acceptingCallId = callId;
          onAccept(callId, isVideo);
          break;

        case Event.actionCallDecline:
          final callId = event.body['id'] as String;
          decliningCallId = callId;
          onDecline(callId);
          break;

        default:
          break;
      }
    });
  }
}
