import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:zego_zim/zego_zim.dart';
import 'package:chating/config/zego_config.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/models/app_user.dart';

class ZimMessage {
  final String fromUserID;
  final String text;
  final int timestamp;
  final bool isMine;

  ZimMessage({
    required this.fromUserID,
    required this.text,
    required this.timestamp,
    required this.isMine,
  });

  Map<String, dynamic> toMap() => {
        'fromUserID': fromUserID,
        'text': text,
        'timestamp': timestamp,
        'isMine': isMine,
      };
}

class ZimService {
  static final ZimService _instance = ZimService._internal();
  factory ZimService() => _instance;
  ZimService._internal();

  bool _isInitialized = false;
  String? _currentUserID;
  String? _currentUserName;

  // Broadcast stream so multiple screens can listen
  final _msgController = StreamController<ZimMessage>.broadcast();
  Stream<ZimMessage> get messageStream => _msgController.stream;

  Future<void> init({
    required String userID,
    required String userName,
  }) async {
    if (_isInitialized && _currentUserID == userID) {
      print('✅ ZimService already initialized for $userID');
      return;
    }

    _currentUserName = userName;

    try {
      // Create / get ZIM instance with In-App Chat credentials
      ZIMAppConfig config = ZIMAppConfig()
        ..appID = ZegoConfig.zimAppID
        ..appSign = ZegoConfig.zimAppSign;
      ZIM.create(config);

      // Wire incoming peer-message handler before login
      ZIMEventHandler.onPeerMessageReceived =
          (ZIM zim, List<ZIMMessage> messages, ZIMMessageReceivedInfo info,
              String fromUserID) {
        for (final msg in messages) {
          if (msg is ZIMTextMessage) {
            _msgController.add(ZimMessage(
              fromUserID: fromUserID,
              text: msg.message,
              timestamp: msg.timestamp,
              isMine: false,
            ));

            if (_currentUserID != null) {
              final senderUID = fromUserID;
              final previewText = msg.message.startsWith('[IMAGE]:') ? '📷 Image' : msg.message;
              final mockUser = AppUser(uid: senderUID, displayName: '', email: '');

              UserService.getUserData(mockUser).then((senderProfile) {
                if (senderProfile != null) {
                  UserService.saveConversation(
                    myUID: _currentUserID!,
                    targetProfile: senderProfile,
                  ).then((_) {
                    UserService.updateConversationLastMessage(
                      myUID: _currentUserID!,
                      targetUID: senderUID,
                      message: previewText,
                    );
                  });
                }
              });
            }
          }
        }
      };

      // Login — ZIM 2.x: login(String userID, ZIMLoginConfig)
      final loginConfig = ZIMLoginConfig()..userName = userName;
      await ZIM.getInstance()!.login(userID, loginConfig);

      _isInitialized = true;
      _currentUserID = userID;
      print('✅ ZimService initialized for $userID');

      // Register FCM token with ZIM for offline message push
      await _registerFCMToken();
    } catch (e) {
      print('❌ ZimService init error: $e');
    }
  }

  // ── FCM Token ──────────────────────────────────────────────────────────────

  /// Retrieves the FCM token and logs it for reference.
  /// ZIM offline push delivery is handled by the ZegoCloud backend
  /// automatically once the FCM Service Account is uploaded to the console.
  Future<void> _registerFCMToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      print('✅ ZimService: FCM token ready — $token');

      // Refresh token listener
      FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
        print('🔄 ZimService: FCM token refreshed');
      });
    } catch (e) {
      print('⚠️ ZimService: FCM token error: $e');
    }
  }

  // ── Send Message ────────────────────────────────────────────────────────────

  /// Send a plain text message to [toUserID].
  /// Includes [ZIMPushConfig] so ZIM delivers an FCM push if recipient is offline.
  Future<bool> sendTextMessage(
    String toUserID,
    String text, {
    String? recipientName,
  }) async {
    if (!_isInitialized) return false;
    try {
      final msg = ZIMTextMessage(message: text);

      final sendConfig = ZIMMessageSendConfig()
        ..pushConfig = (ZIMPushConfig()
          ..resourcesID = 'zim_offline_push'
          ..title = _currentUserName ?? 'New Message'
          ..content = text.length > 80 ? '${text.substring(0, 80)}…' : text
          ..payload = jsonEncode({
            'sender_id': _currentUserID,
            'sender_name': _currentUserName,
            'click_action': 'open_chat',
          }));

      await ZIM.getInstance()!.sendMessage(
        msg,
        toUserID,
        ZIMConversationType.peer,
        sendConfig,
      );
      return true;
    } catch (e) {
      print('❌ ZimService sendTextMessage error: $e');
      return false;
    }
  }

  // ── Query History ──────────────────────────────────────────────────────────

  /// Load the last [count] messages exchanged with [targetUserID].
  Future<List<ZimMessage>> queryHistory(String targetUserID,
      {int count = 100}) async {
    if (!_isInitialized) return [];
    try {
      final config = ZIMMessageQueryConfig()
        ..count = count
        ..reverse = true;

      final result = await ZIM.getInstance()!.queryHistoryMessage(
        targetUserID,
        ZIMConversationType.peer,
        config,
      );

      // Returned newest-first; keep it that way for the reverse ListView.
      final messages = result.messageList
          .whereType<ZIMTextMessage>()
          .map((m) => ZimMessage(
                fromUserID: m.senderUserID,
                text: m.message,
                timestamp: m.timestamp,
                isMine: m.senderUserID == _currentUserID,
              ))
          .toList();
      return messages;
    } catch (e) {
      print('❌ ZimService queryHistory error: $e');
      return [];
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  void logout() {
    if (!_isInitialized) return;
    try {
      ZIM.getInstance()?.logout();
    } catch (_) {}
    _isInitialized = false;
    _currentUserID = null;
  }

  String? get currentUserID => _currentUserID;
  bool get isInitialized => _isInitialized;
}
