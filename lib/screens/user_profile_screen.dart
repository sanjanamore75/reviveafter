import 'package:flutter/material.dart';
import 'package:chating/models/app_user.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/screens/chat_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> targetUser;
  final AppUser currentUser;
  final Future<void> Function(Map<String, dynamic> profile,
      {required bool isVideoCall})? onCallUser;

  const UserProfileScreen({
    super.key,
    required this.targetUser,
    required this.currentUser,
    this.onCallUser,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-save this profile as a conversation so it appears in Messages tab
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await UserService.saveConversation(
        myUID: widget.currentUser.uid,
        targetProfile: widget.targetUser,
      );
    });
  }

  void _showActionDialog(String title, String message, Color color) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(title, style: TextStyle(color: color)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('$title Successful'), backgroundColor: color),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: Text(title),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.targetUser['uid'] ?? '';

    return StreamBuilder<Map<String, dynamic>?>(
      stream: UserService.getUserStream(uid),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? widget.targetUser;
        final name = profile['name'] ?? 'User';
        final photoURL = profile['photoURL'] as String?;
        final status = profile['status'] ?? 'online';

        return Scaffold(
          backgroundColor: const Color(0xFF0F0C29),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
              ),
            ),
            child: Column(
              children: [
                // Custom App Bar / Header
                _buildHeader(context, name, photoURL, status),

                // Main Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Calling Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildCallAction(
                              icon: Icons.videocam_rounded,
                              label: 'Video',
                              color: const Color(0xFF6C63FF),
                              onTap: () => Navigator.pop(context, 'video'),
                            ),
                            _buildCallAction(
                              icon: Icons.call_rounded,
                              label: 'Voice',
                              color: const Color(0xFF00C9A7),
                              onTap: () => Navigator.pop(context, 'voice'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),

                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Send a Message',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          currentUser: widget.currentUser,
                                          targetProfile: profile,
                                          onCallUser: widget.onCallUser ??
                                              (p, {required isVideoCall}) async {
                                                Navigator.pop(
                                                    context,
                                                    isVideoCall
                                                        ? 'video'
                                                        : 'voice');
                                              },
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.chat_rounded, size: 18),
                                  label: const Text('Open Chat'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6C63FF),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Safety Actions
                        Row(
                          children: [
                            Expanded(
                              child: _buildSafetyBtn(
                                icon: Icons.block_flipped,
                                label: 'Block User',
                                color: Colors.orangeAccent,
                                onTap: () => _showActionDialog(
                                    'Block',
                                    'Are you sure you want to block $name? They won\'t be able to contact you.',
                                    Colors.orangeAccent),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildSafetyBtn(
                                icon: Icons.report_problem_rounded,
                                label: 'Report User',
                                color: Colors.redAccent,
                                onTap: () => _showActionDialog(
                                    'Report',
                                    'Report $name for inappropriate behavior?',
                                    Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, String name, String? photoURL, String status) {
    final isBusy = status == 'busy';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
            ),
            const SizedBox(width: 12),
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                      ? NetworkImage(photoURL)
                      : null,
                  backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  child: photoURL == null
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Color(0xFF6C63FF)))
                      : null,
                ),
                if (isBusy)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF0F0C29), width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  Text(isBusy ? 'Busy' : 'Online',
                      style: TextStyle(
                          color: isBusy ? Colors.orangeAccent : const Color(0xFF00C9A7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallAction(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.1),
                    blurRadius: 15,
                    spreadRadius: 2)
              ],
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildSafetyBtn(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
