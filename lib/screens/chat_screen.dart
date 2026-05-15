import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:chating/services/zim_service.dart';
import 'package:chating/services/user_service.dart';

class ChatScreen extends StatefulWidget {
  final User currentUser;
  final Map<String, dynamic> targetProfile;
  final Future<void> Function(Map<String, dynamic> profile,
      {required bool isVideoCall}) onCallUser;

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.targetProfile,
    required this.onCallUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ZimService _zim = ZimService();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  StreamSubscription<ZimMessage>? _sub;

  String get _targetUID => widget.targetProfile['uid']?.toString() ?? '';
  String get _targetName => widget.targetProfile['name'] ?? 'User';
  String? get _targetPhoto => widget.targetProfile['photoURL'] as String?;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Listen for real-time incoming messages from this specific user
    _sub = _zim.messageStream
        .where((m) => m.fromUserID == _targetUID)
        .listen((msg) {
      setState(() => _messages.insert(0, msg.toMap()));
      // No need to scroll manually with reverse: true for new messages
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await _zim.queryHistory(_targetUID);
    if (mounted) {
      setState(() {
        _messages = history.map((m) => m.toMap()).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // 1. Clear input and add to UI instantly (Optimistic Update)
    _textController.clear();
    setState(() {
      _messages.insert(0, {
        'fromUserID': widget.currentUser.uid,
        'text': text,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isMine': true,
      });
    });

    // 2. Send via ZIM in the background
    final success = await _zim.sendTextMessage(_targetUID, text);
    
    if (success) {
      // Update last message preview in Firebase
      await UserService.updateConversationLastMessage(
        myUID: widget.currentUser.uid,
        targetUID: _targetUID,
        message: text,
      );
    } else {
      // Handle failure (optional: remove message or show error)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    }
  }


  void _initiateCall({required bool isVideo}) {
    widget.onCallUser(widget.targetProfile, isVideoCall: isVideo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0C29), Color(0xFF1A1A3E), Color(0xFF24243E)],
          ),
        ),
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(child: _isLoading ? _buildLoader() : _buildMessageList()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final photo = _targetPhoto;
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
            ),
            CircleAvatar(
              radius: 22,
              backgroundImage: (photo != null && photo.isNotEmpty)
                  ? NetworkImage(photo)
                  : null,
              backgroundColor: const Color(0xFF6C63FF).withOpacity(0.3),
              child: (photo == null || photo.isEmpty)
                  ? Text(_targetName.isNotEmpty ? _targetName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_targetName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const Text('Tap to view profile',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            // Voice call
            _buildCallBtn(
              icon: Icons.call_rounded,
              color: const Color(0xFF00C9A7),
              onTap: () => _initiateCall(isVideo: false),
            ),
            const SizedBox(width: 4),
            // Video call
            _buildCallBtn(
              icon: Icons.videocam_rounded,
              color: const Color(0xFF6C63FF),
              onTap: () => _initiateCall(isVideo: true),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildCallBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 80, color: Colors.white.withOpacity(0.08)),
            const SizedBox(height: 16),
            Text('Say hello to $_targetName! 👋',
                style:
                    const TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Messages are end-to-end encrypted.',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMine = msg['isMine'] == true;
        final text = msg['text'] ?? '';
        final ts = msg['timestamp'] as int? ?? 0;

        // Show date separator if needed (check message above - which is index + 1 in reverse list)
        final showDate = index == _messages.length - 1 ||
            _isDifferentDay(
                _messages[index + 1]['timestamp'] as int? ?? 0, ts);

        return Column(
          children: [
            if (showDate) _buildDateSeparator(ts),
            _buildBubble(text: text, isMine: isMine, timestamp: ts),
          ],
        );
      },
    );
  }

  bool _isDifferentDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.day != d2.day ||
        d1.month != d2.month ||
        d1.year != d2.year;
  }

  Widget _buildDateSeparator(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    String label;
    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      label = 'Today';
    } else if (date.day == now.day - 1 &&
        date.month == now.month &&
        date.year == now.year) {
      label = 'Yesterday';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
              child: Divider(color: Colors.white.withOpacity(0.1))),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Expanded(
              child: Divider(color: Colors.white.withOpacity(0.1))),
        ],
      ),
    );
  }

  Widget _buildBubble(
      {required String text,
      required bool isMine,
      required int timestamp}) {
    final time = _formatTime(timestamp);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        margin: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isMine ? 60 : 0,
          right: isMine ? 0 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMine
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF4F8EF7)],
                )
              : null,
          color: isMine ? null : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          border: isMine
              ? null
              : Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4)),
            const SizedBox(height: 4),
            Text(time,
                style: TextStyle(
                    color: isMine
                        ? Colors.white.withOpacity(0.55)
                        : Colors.white38,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    if (timestamp == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.08))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
                    hintStyle:
                        TextStyle(color: Colors.white.withOpacity(0.25)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF4F8EF7)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
