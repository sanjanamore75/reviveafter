import 'package:flutter/material.dart';
import 'package:chating/models/app_user.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/screens/chat_screen.dart';

class MessagesScreen extends StatelessWidget {
  final AppUser currentUser;
  final Future<void> Function(Map<String, dynamic> profile,
      {required bool isVideoCall}) onCallUser;

  const MessagesScreen({
    super.key,
    required this.currentUser,
    required this.onCallUser,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Messages',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Your conversations',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ),
            ),
            // Conversation list
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: UserService.getUnifiedHistory(currentUser.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF6C63FF)));
                  }

                  final convs = snapshot.data ?? [];

                  if (convs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 90,
                              color: Colors.white.withValues(alpha: 0.08)),
                          const SizedBox(height: 20),
                          const Text('No conversations yet',
                              style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          const Text(
                            'Tap any profile on the Profiles tab\nto start a conversation.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white24, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: convs.length,
                    itemBuilder: (context, i) => _ConversationTile(
                      conv: convs[i],
                      currentUser: currentUser,
                      onCallUser: onCallUser,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Single Conversation Row ─────────────────────────────────────────────────
class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conv;
  final AppUser currentUser;
  final Future<void> Function(Map<String, dynamic>, {required bool isVideoCall})
      onCallUser;

  const _ConversationTile({
    required this.conv,
    required this.currentUser,
    required this.onCallUser,
  });

  @override
  Widget build(BuildContext context) {
    final isCall = conv.containsKey('callerId');
    final targetUID = (conv['uid'] ?? conv['callerId'])?.toString() ?? '';

    return StreamBuilder<Map<String, dynamic>?>(
      stream: UserService.getUserStream(targetUID),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final name = profile?['name'] as String? ??
            (isCall ? (conv['callerName'] ?? 'User') : (conv['name'] ?? 'User'));
        final photo = profile?['photoURL'] as String? ??
            (isCall ? (conv['callerPhoto'] as String?) : (conv['photoURL'] as String?));

        var lastMsg = isCall ? '' : (conv['lastMessage'] ?? '');
        if (lastMsg.startsWith('[IMAGE]:')) {
          lastMsg = '📷 Image';
        }
        final timestamp = (conv['lastActivity'] ?? conv['timestamp']) as int? ?? 0;
        final timeStr = _formatTime(timestamp);

        final status = conv['status'] as String?;
        final isVideo = conv['isVideo'] == true;

        return GestureDetector(
          onTap: () {
            if (isCall) {
              // If it's a call log, maybe navigate to profile or call back
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    currentUser: currentUser,
                    targetProfile: {
                      'uid': targetUID,
                      'name': name,
                      'photoURL': photo,
                    },
                    onCallUser: onCallUser,
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    currentUser: currentUser,
                    targetProfile: {
                      ...conv,
                      'name': name,
                      'photoURL': photo,
                    },
                    onCallUser: onCallUser,
                  ),
                ),
              );
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isCall
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: (photo != null && photo.isNotEmpty)
                          ? NetworkImage(photo)
                          : null,
                      backgroundColor:
                          const Color(0xFF6C63FF).withValues(alpha: 0.2),
                      child: (photo == null || photo.isEmpty)
                          ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                              style: const TextStyle(
                                  color: Color(0xFF6C63FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18))
                          : null,
                    ),
                    if (!isCall)
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: (profile?['status'] == 'busy')
                                ? Colors.orangeAccent
                                : const Color(0xFF00C9A7),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFF1a1a2e), width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                // Name + last message / call info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      if (isCall)
                        Row(
                          children: [
                            Icon(
                              isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.call_rounded,
                              size: 14,
                              color: status == 'missed'
                                  ? Colors.redAccent
                                  : Colors.white38,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status?.toUpperCase() ?? 'CALL',
                              style: TextStyle(
                                color: status == 'missed'
                                    ? Colors.redAccent
                                    : Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          lastMsg.isEmpty ? 'Tap to chat 💬' : lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: lastMsg.isEmpty
                                  ? Colors.white24
                                  : Colors.white54,
                              fontSize: 13,
                              fontStyle: lastMsg.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Timestamp + call buttons
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(timeStr,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _SmallCallBtn(
                          icon: Icons.call_rounded,
                          color: const Color(0xFF00C9A7),
                          onTap: () {
                            final targetProfile = isCall
                                ? {
                                    'uid': targetUID,
                                    'name': name,
                                    'photoURL': photo,
                                  }
                                : {
                                    ...conv,
                                    'name': name,
                                    'photoURL': photo,
                                  };
                            onCallUser(targetProfile, isVideoCall: false);
                          },
                        ),
                        const SizedBox(width: 6),
                        _SmallCallBtn(
                          icon: Icons.videocam_rounded,
                          color: const Color(0xFF6C63FF),
                          onTap: () {
                            final targetProfile = isCall
                                ? {
                                    'uid': targetUID,
                                    'name': name,
                                    'photoURL': photo,
                                  }
                                : {
                                    ...conv,
                                    'name': name,
                                    'photoURL': photo,
                                  };
                            onCallUser(targetProfile, isVideoCall: true);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${date.day}/${date.month}';
  }
}

class _SmallCallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SmallCallBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}
