import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:chating/services/auth_service.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/models/app_user.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:chating/services/zego_service.dart';
import 'package:chating/services/permission_service.dart';
import 'package:chating/screens/spoof_login_screen.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:chating/screens/chat_screen.dart';
import 'package:chating/services/zim_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();

  String _selectedGender = 'female';
  String _selectedStatus = 'mix';
  bool _useImageUrl = false;
  File? _pickedImage;
  bool _isSaving = false;

  bool _isSpoofing = false;
  String _spoofName = '';
  bool _permissionsGranted = true;
  String _rightView = 'profiles';

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _initZego();
    UserService.randomizeStatusesIfAllOnline();
  }

  Future<void> _checkPermissions() async {
    final granted = await PermissionService.checkAllPermissions();
    setState(() => _permissionsGranted = granted);
  }

  Future<void> _requestPermissions() async {
    await PermissionService.requestAllPermissions();
    await _checkPermissions();
  }

  Future<void> _initZego() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await ZegoService().init(
        userID: user.uid,
        userName: 'Admin',
      );
      if (mounted) {
        await UserService.saveProfile(
          user: AppUser.fromFirebaseUser(user),
          gender: 'admin',
        );
        _showSnack('Admin Zego online (UID: ${user.uid})', isError: false);
      }
    }
  }

  Future<void> _restoreAdminIdentity() async {
    if (!_isSpoofing) return;
    setState(() {
      _isSpoofing = false;
      _spoofName = '';
    });
    ZegoUIKitPrebuiltCallInvitationService().uninit();
    await _initZego();

    // Re-initialize ZimService for Admin
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final displayName =
          user.displayName ?? user.email?.split('@').first ?? 'Admin';
      await ZimService().init(
        userID: user.uid,
        userName: displayName,
      );
    }

    _showSnack(
        'Identity restored to Admin (Receiving calls/messages again)',
        isError: false);
  }

  Future<void> _initiateSpoofedCall(
      Map<String, dynamic> seedProfile, Map<String, dynamic> targetUser,
      {required bool isVideo}) async {
    setState(() {
      _isSpoofing = true;
      _spoofName = seedProfile['name'] ?? 'Profile';
    });

    // Clean current session
    ZegoUIKitPrebuiltCallInvitationService().uninit();

    // Init Zego as the seed profile
    await ZegoService().init(
      userID: seedProfile['uid'],
      userName: seedProfile['name'] ?? 'Profile',
    );

    // Init ZimService as the seed profile
    await ZimService().init(
      userID: seedProfile['uid'],
      userName: seedProfile['name'] ?? 'Profile',
    );

    // Send the fake invite
    final success = await ZegoUIKitPrebuiltCallInvitationService().send(
      invitees: [ZegoCallUser(targetUser['uid'], targetUser['name'] ?? 'User')],
      isVideoCall: isVideo,
      resourceID: 'zego_call',
    );
    if (!success) {
      _showSnack('User is offline or unavailable', isError: true);
    }
  }

  Future<void> _initiateSpoofedChat(
      Map<String, dynamic> seedProfile, Map<String, dynamic> targetUser) async {
    setState(() {
      _isSpoofing = true;
      _spoofName = seedProfile['name'] ?? 'Profile';
    });

    // Clean current session
    ZegoUIKitPrebuiltCallInvitationService().uninit();

    // Init Zego as the seed profile
    await ZegoService().init(
      userID: seedProfile['uid'],
      userName: seedProfile['name'] ?? 'Profile',
    );

    // Init ZimService as the seed profile
    await ZimService().init(
      userID: seedProfile['uid'],
      userName: seedProfile['name'] ?? 'Profile',
    );

    // Open ChatScreen
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            currentUser: AppUser(
              uid: seedProfile['uid'] ?? '',
              displayName: seedProfile['name'] ?? '',
              email: 'admin_seed@example.com',
              isSeed: true,
            ),
            targetProfile: targetUser,
            onCallUser: (profile, {required bool isVideoCall}) async {
              await _initiateSpoofedCall(
                seedProfile,
                profile,
                isVideo: isVideoCall,
              );
            },
          ),
        ),
      );
    }
  }

  void _showRealUsersDialog(Map<String, dynamic> seedProfile) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: Text('Call / Message a user as ${seedProfile['name']}',
                  style: const TextStyle(color: Colors.white, fontSize: 18)),
              content: SizedBox(
                  width: double.maxFinite,
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: UserService.realUsersStream(),
                      builder: (ctx, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF6C63FF)));
                        }
                        final users = snapshot.data ?? [];
                        if (users.isEmpty) {
                          return const Text('No real users found',
                              style: TextStyle(color: Colors.white54));
                        }

                        return ListView.builder(
                            shrinkWrap: true,
                            itemCount: users.length,
                            itemBuilder: (ctx, i) {
                              final u = users[i];
                              return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF6C63FF)
                                        .withValues(alpha: 0.3),
                                    backgroundImage: (u['photoURL'] != null &&
                                            u['photoURL'].toString().isNotEmpty)
                                        ? NetworkImage(u['photoURL'])
                                        : null,
                                    child: (u['photoURL'] == null ||
                                            u['photoURL'].toString().isEmpty)
                                        ? Text(
                                            (u['name'] != null &&
                                                    u['name']
                                                        .toString()
                                                        .isNotEmpty)
                                                ? u['name']
                                                    .toString()[0]
                                                    .toUpperCase()
                                                : 'U',
                                            style: const TextStyle(
                                                color: Colors.white))
                                        : null,
                                  ),
                                  title: Text(u['name'] ?? 'User',
                                      style:
                                          const TextStyle(color: Colors.white)),
                                  subtitle: Text(u['uid'],
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 10)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                          icon: const Icon(
                                              Icons.videocam_rounded,
                                              color: Color(0xFF6C63FF)),
                                          tooltip: 'Video Call',
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(6),
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            _initiateSpoofedCall(seedProfile, u,
                                                isVideo: true);
                                          }),
                                      IconButton(
                                          icon: const Icon(Icons.call_rounded,
                                              color: Color(0xFF00C9A7)),
                                          tooltip: 'Voice Call',
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(6),
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            _initiateSpoofedCall(seedProfile, u,
                                                isVideo: false);
                                          }),
                                      IconButton(
                                          icon: const Icon(
                                              Icons.chat_bubble_rounded,
                                              color: Color(0xFFFFB74D)),
                                          tooltip: 'Message',
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(6),
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            _initiateSpoofedChat(seedProfile, u);
                                          }),
                                    ],
                                  ));
                            });
                      })),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54)),
                )
              ],
            ));
  }

  void _showProfileHistory(Map<String, dynamic> seedProfile) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: Text('History for ${seedProfile['name']}',
                  style: const TextStyle(color: Colors.white, fontSize: 18)),
              content: SizedBox(
                width: double.maxFinite,
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: UserService.getUnifiedHistory(seedProfile['uid']),
                  builder: (ctx, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF6C63FF)));
                    }
                    final items = snapshot.data ?? [];
                    if (items.isEmpty)
                      return const Text('No history found',
                          style: TextStyle(color: Colors.white54));

                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final item = items[i];
                        final isCall = item.containsKey('callerId');
                        final title = isCall
                            ? (item['callerName'] ?? 'Unknown Caller')
                            : (item['name'] ?? 'User');
                        final timeMillis =
                            item['lastActivity'] ?? item['timestamp'];
                        final timeStr = timeMillis != null
                            ? DateTime.fromMillisecondsSinceEpoch(
                                    timeMillis as int)
                                .toString()
                                .split('.')[0]
                            : '';
                        final subtitle = isCall
                            ? '${item['status'] == 'missed' ? 'Missed Call' : 'Call'} • $timeStr'
                            : '${item['lastMessage'] ?? 'No messages'} • $timeStr';

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFF6C63FF).withValues(alpha: 0.3),
                            backgroundImage: NetworkImage(isCall
                                ? (item['callerPhoto'] ?? '')
                                : (item['photoURL'] ?? '')),
                          ),
                          title: Text(title,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(subtitle,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          trailing: isCall
                              ? Icon(
                                  item['isVideo'] == true
                                      ? Icons.videocam
                                      : Icons.call,
                                  color: item['status'] == 'missed'
                                      ? Colors.redAccent
                                      : Colors.greenAccent,
                                )
                              : const Icon(Icons.chat_bubble_rounded,
                                  color: Color(0xFF6C63FF)),
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close',
                      style: TextStyle(color: Colors.white54)),
                )
              ],
            ));
  }

  @override
  void dispose() {
    // We don't uninit here to keep background notifications working
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String _convertDriveLink(String url) {
    if (url.contains('drive.google.com/file/d/')) {
      final regExp = RegExp(r'/file/d/([a-zA-Z0-9_-]+)');
      final match = regExp.firstMatch(url);
      if (match != null && match.groupCount >= 1) {
        return 'https://drive.google.com/uc?export=view&id=${match.group(1)}';
      }
    }
    return url;
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<String?> _uploadImage(File file) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('admin_profiles')
          .child(fileName);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      _showSnack('Error uploading image: $e', isError: true);
      return null;
    }
  }

  Future<void> _pushProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Please enter a name');
      return;
    }

    String photoURL = '';
    if (_useImageUrl) {
      photoURL = _urlController.text.trim();
      if (photoURL.isEmpty) {
        _showSnack('Please enter an image URL or choose Upload');
        return;
      }
    } else {
      if (_pickedImage == null) {
        _showSnack('Please pick an image from your device');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      if (!_useImageUrl && _pickedImage != null) {
        final uploadedUrl = await _uploadImage(_pickedImage!);
        if (uploadedUrl == null) {
          setState(() => _isSaving = false);
          return;
        }
        photoURL = uploadedUrl;
      } else {
        photoURL = _convertDriveLink(photoURL);
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showSnack('You must be logged in as admin to push profiles.',
            isError: true);
        return;
      }

      String statusToSave = _selectedStatus;
      if (statusToSave == 'mix') {
        statusToSave = DateTime.now().millisecond % 2 == 0 ? 'online' : 'busy';
      }

      await UserService.addSeedProfile(
        name: name,
        gender: _selectedGender,
        photoURL: photoURL,
        adminUid: currentUser.uid,
        status: statusToSave,
      );

      _showSnack('Profile pushed successfully!', isError: false);

      // Reset form
      setState(() {
        _nameController.clear();
        _urlController.clear();
        _pickedImage = null;
        _selectedStatus = 'mix';
      });
    } catch (e) {
      _showSnack('Failed to push profile: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : const Color(0xFF00C9A7),
    ));
  }

  Future<void> _signOut() async {
    await AuthService().signOut();
  }

  @override
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 750;

    // Adjust view state if switching from mobile 'push' view back to desktop
    if (!isMobile && _rightView == 'push') {
      _rightView = 'profiles';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Admin Panel',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 18)),
            if (_isSpoofing)
              Text('🔥 SPOOFING ACTIVE: Calling as $_spoofName',
                  style: const TextStyle(
                      color: Color(0xFFFFB74D),
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF16213e),
        actions: [
          if (_isSpoofing)
            ElevatedButton.icon(
              onPressed: _restoreAdminIdentity,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB74D).withValues(alpha: 0.2),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.refresh_rounded,
                  color: Color(0xFFFFB74D), size: 16),
              label: const Text('Restore Admin',
                  style: TextStyle(color: Color(0xFFFFB74D), fontSize: 12)),
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SpoofLoginScreen()),
              );
            },
            icon:
                const Icon(Icons.people_alt_rounded, color: Color(0xFF6C63FF)),
            tooltip: 'Spoof Login',
          ),
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFFF6B6B)),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_permissionsGranted) _buildPermissionBanner(),
          Expanded(
            child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left side: Create form
        Expanded(
          flex: 1,
          child: Container(
            color: const Color(0xFF16213e).withValues(alpha: 0.5),
            padding: const EdgeInsets.all(24),
            child: _buildPushForm(),
          ),
        ),
        // Right side: Profile List & Live Alerts
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDesktopSwitcher(),
                if (_rightView == 'profiles') ...[
                  _buildProfilesHeader(),
                  const SizedBox(height: 20),
                  Expanded(child: _buildProfilesList()),
                ] else ...[
                  _buildAlertsHeader(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _buildLiveAlertsFeed(
                        FirebaseAuth.instance.currentUser?.uid ?? ''),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    // If state was left in desktop mode but now on mobile, ensure valid tab is selected
    if (_rightView != 'push' && _rightView != 'profiles' && _rightView != 'alerts') {
      _rightView = 'profiles';
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMobileSwitcher(),
          const SizedBox(height: 16),
          Expanded(
            child: _rightView == 'push'
                ? _buildPushForm()
                : _rightView == 'profiles'
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfilesHeader(),
                          const SizedBox(height: 16),
                          Expanded(child: _buildProfilesList()),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAlertsHeader(),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildLiveAlertsFeed(
                                FirebaseAuth.instance.currentUser?.uid ?? ''),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPushForm() {
    return ListView(
      children: [
        const Text('Push New Profile',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),

        // Name Input
        _buildLabel('Name'),
        _buildTextField(controller: _nameController, hint: 'E.g. Sarah'),
        const SizedBox(height: 16),

        // Gender Selector
        _buildLabel('Gender'),
        Row(
          children: [
            Expanded(
                child: _buildGenderChoice(
                    'male', '👨 Male', const Color(0xFF4F8EF7))),
            const SizedBox(width: 12),
            Expanded(
                child: _buildGenderChoice(
                    'female', '👩 Female', const Color(0xFFE91E8C))),
          ],
        ),
        const SizedBox(height: 20),

        // Status Selector
        _buildLabel('Status'),
        Row(
          children: [
            Expanded(
                child: _buildStatusChoice(
                    'online', '🟢 Online', const Color(0xFF00C9A7))),
            const SizedBox(width: 8),
            Expanded(
                child: _buildStatusChoice(
                    'busy', '🟠 Busy', Colors.orangeAccent)),
            const SizedBox(width: 8),
            Expanded(
                child: _buildStatusChoice(
                    'mix', '🔀 Mix', Colors.purpleAccent)),
          ],
        ),
        const SizedBox(height: 20),

        // Image Source Toggle
        _buildLabel('Picture Source'),
        Row(
          children: [
            Expanded(
              child: RadioListTile<bool>(
                title: const Text('Upload Image',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                value: false,
                groupValue: _useImageUrl,
                activeColor: const Color(0xFF6C63FF),
                onChanged: (val) => setState(() => _useImageUrl = val!),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: RadioListTile<bool>(
                title: const Text('Image URL',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                value: true,
                groupValue: _useImageUrl,
                activeColor: const Color(0xFF6C63FF),
                onChanged: (val) => setState(() => _useImageUrl = val!),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Picture Input
        if (_useImageUrl)
          _buildTextField(
              controller: _urlController, hint: 'Paste image URL here...')
        else
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: _pickedImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(_pickedImage!, fit: BoxFit.cover))
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded,
                            color: Colors.white54, size: 36),
                        SizedBox(height: 8),
                        Text('Tap to pick an image',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 13)),
                      ],
                    ),
            ),
          ),

        const SizedBox(height: 32),

        // Push Button
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _pushProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _isSaving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Push Profile',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilesHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Pushed Profiles',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        TextButton.icon(
          onPressed: () async {
            final snap = await UserService.seedProfilesStream().first;
            for (int i = 0; i < snap.length; i++) {
              final newStatus = i % 2 == 0 ? 'online' : 'busy';
              final uid = snap[i]['uid'];
              if (uid != null) {
                await UserService.getUserRef(
                        AppUser(uid: uid, displayName: '', email: ''))
                    .update({'status': newStatus});
              }
            }
            _showSnack('Statuses randomized successfully!', isError: false);
          },
          icon: const Icon(Icons.shuffle, color: Color(0xFF6C63FF), size: 16),
          label: const Text('Randomize Tags',
              style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildAlertsHeader() {
    return const Row(
      children: [
        Text('Real-Time Live Alerts',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDesktopSwitcher() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _rightView = 'profiles'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _rightView == 'profiles'
                      ? const Color(0xFF6C63FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('Pushed Profiles',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _rightView = 'alerts'),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: UserService.adminAlertsStream(
                      FirebaseAuth.instance.currentUser?.uid ?? ''),
                  builder: (context, snapshot) {
                    final alertCount = snapshot.data?.length ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _rightView == 'alerts'
                            ? const Color(0xFF6C63FF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Live Alerts',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          if (alertCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                alertCount.toString(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSwitcher() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _rightView = 'push'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _rightView == 'push'
                      ? const Color(0xFF6C63FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('Push',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _rightView = 'profiles'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _rightView == 'profiles'
                      ? const Color(0xFF6C63FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('Profiles',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _rightView = 'alerts'),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: UserService.adminAlertsStream(
                      FirebaseAuth.instance.currentUser?.uid ?? ''),
                  builder: (context, snapshot) {
                    final alertCount = snapshot.data?.length ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _rightView == 'alerts'
                            ? const Color(0xFF6C63FF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Alerts',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          if (alertCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                alertCount.toString(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilesList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: UserService.seedProfilesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
        }
        final profiles = snapshot.data ?? [];
        if (profiles.isEmpty) {
          return const Center(
              child: Text('No pushed profiles yet.',
                  style: TextStyle(color: Colors.white54)));
        }

        return ListView.builder(
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final p = profiles[index];
            final isFemale = p['gender'] == 'female';
            final photoURL = p['photoURL']?.toString() ?? '';
            final name = p['name']?.toString() ?? 'Pushed Profile';
            final uid = p['uid']?.toString() ?? '';

            return StreamBuilder<List<Map<String, dynamic>>>(
                stream: UserService.getUnifiedHistory(uid),
                builder: (context, historySnap) {
                  final history = historySnap.data ?? [];
                  final hasAlerts = history.isNotEmpty;
                  final alertCount = history.length;

                  return ListTile(
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          backgroundColor: isFemale
                              ? const Color(0xFFE91E8C).withValues(alpha: 0.3)
                              : const Color(0xFF4F8EF7).withValues(alpha: 0.3),
                          backgroundImage: photoURL.isNotEmpty
                              ? NetworkImage(photoURL)
                              : null,
                          child: photoURL.isEmpty
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                  style: const TextStyle(color: Colors.white))
                              : null,
                        ),
                        if (p['status'] == 'busy')
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFF1a1a2e), width: 1.5),
                              ),
                            ),
                          ),
                        if (hasAlerts)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                alertCount > 9 ? '9+' : alertCount.toString(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            if (uid.isEmpty) return;
                            final newStatus =
                                p['status'] == 'busy' ? 'online' : 'busy';
                            await UserService.getUserRef(
                              AppUser(
                                uid: uid,
                                displayName: '',
                                email: '',
                              ),
                            ).update({'status': newStatus});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (p['status'] == 'busy'
                                      ? Colors.orangeAccent
                                      : const Color(0xFF00C9A7))
                                  .withValues(alpha: 0.15),
                              border: Border.all(
                                  color: p['status'] == 'busy'
                                      ? Colors.orangeAccent
                                      : const Color(0xFF00C9A7),
                                  width: 1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              p['status'] == 'busy' ? 'Busy' : 'Online',
                              style: TextStyle(
                                  color: p['status'] == 'busy'
                                      ? Colors.orangeAccent
                                      : const Color(0xFF00C9A7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(uid,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.history_rounded,
                              color: hasAlerts ? Colors.amber : Colors.white38),
                          tooltip: 'View History',
                          onPressed: () => _showProfileHistory(p),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                        IconButton(
                          icon: const Icon(Icons.wifi_calling_3_rounded,
                              color: Color(0xFF00C9A7)),
                          tooltip: 'Call a user as this profile',
                          onPressed: () => _showRealUsersDialog(p),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_rounded,
                              color: Colors.white38),
                          tooltip: 'Delete Profile',
                          onPressed: () {
                            if (uid.isNotEmpty) {
                              UserService.deleteProfile(uid);
                            }
                          },
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                      ],
                    ),
                  );
                });
          },
        );
      },
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.amber.withValues(alpha: 0.9),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.black87),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Permissions required for background calls',
              style: TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: _requestPermissions,
            style: TextButton.styleFrom(
              backgroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Grant All',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTextField(
      {required TextEditingController controller, required String hint}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF666666), fontSize: 14),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildGenderChoice(String gender, String label, Color color) {
    final isSelected = _selectedGender == gender;
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = gender),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? color : Colors.white12),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: isSelected ? color : Colors.white54,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStatusChoice(String status, String label, Color color) {
    final isSelected = _selectedStatus == status;
    return GestureDetector(
      onTap: () => setState(() => _selectedStatus = status),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? color : Colors.white12),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: isSelected ? color : Colors.white54,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLiveAlertsFeed(String adminUid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: UserService.adminAlertsStream(adminUid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
          );
        }

        final alerts = snapshot.data ?? [];
        if (alerts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none_rounded,
                    size: 64, color: Colors.white24),
                SizedBox(height: 16),
                Text('No active calls or messages.',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: alerts.length,
          itemBuilder: (context, index) {
            final alert = alerts[index];
            final type = alert['type'] ?? 'call';
            final isCall = type == 'call';
            final timestamp = alert['timestamp'] as int? ?? 0;
            final timeStr = timestamp > 0
                ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                    .toString()
                    .split('.')[0]
                    .substring(11, 16)
                : '';

            final seedUid = alert['seedUid'] ?? '';
            final seedName = alert['seedName'] ?? 'Seed';
            final seedPhoto = alert['seedPhoto'] ?? '';

            final callerId = alert['callerId'] ?? '';
            final callerName = alert['callerName'] ?? 'User';
            final callerPhoto = alert['callerPhoto'] ?? '';
            final status = alert['status'] ?? ''; // for calls: status, for messages: text

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.white.withValues(alpha: 0.03),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isCall
                      ? const Color(0xFF00C9A7).withValues(alpha: 0.15)
                      : const Color(0xFF6C63FF).withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Target Pushed Profile (Seed) Small Avatar
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundImage: seedPhoto.isNotEmpty
                                  ? NetworkImage(seedPhoto)
                                  : null,
                              backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                              child: seedPhoto.isEmpty
                                  ? Text(seedName.isNotEmpty ? seedName[0].toUpperCase() : 'S',
                                      style: const TextStyle(color: Colors.white, fontSize: 12))
                                  : null,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1a1a2e),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isCall ? Icons.phone_callback_rounded : Icons.chat_bubble_outline_rounded,
                                  size: 10,
                                  color: isCall ? const Color(0xFF00C9A7) : const Color(0xFF6C63FF),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$seedName received a ${isCall ? 'call' : 'message'}',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundImage: callerPhoto.isNotEmpty
                                        ? NetworkImage(callerPhoto)
                                        : null,
                                    backgroundColor: Colors.white12,
                                    child: callerPhoto.isEmpty
                                        ? Text(callerName.isNotEmpty ? callerName[0].toUpperCase() : 'U',
                                            style: const TextStyle(color: Colors.white, fontSize: 8))
                                        : null,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'From: $callerName',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          timeStr,
                          style: const TextStyle(color: Colors.white30, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            isCall
                                ? 'Status: ${status.toString().toUpperCase()}'
                                : 'Text: "$status"',
                            style: TextStyle(
                              color: isCall
                                  ? (status == 'missed' ? Colors.redAccent : Colors.greenAccent)
                                  : Colors.white70,
                              fontSize: 12,
                              fontStyle: isCall ? FontStyle.normal : FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          children: [
                            // Action: Spoof & Respond
                            ElevatedButton.icon(
                              onPressed: () async {
                                // 1. Clean Zego session
                                ZegoUIKitPrebuiltCallInvitationService().uninit();

                                // 2. Log in as seed
                                await ZegoService().init(
                                  userID: seedUid,
                                  userName: seedName,
                                );
                                await ZimService().init(
                                  userID: seedUid,
                                  userName: seedName,
                                );

                                // 3. Update local state
                                setState(() {
                                  _isSpoofing = true;
                                  _spoofName = seedName;
                                });

                                // 4. Fetch target user profile
                                final targetUser = AppUser(uid: callerId, displayName: callerName, email: '');
                                final targetProfile = await UserService.getUserData(targetUser);

                                if (targetProfile == null) {
                                  _showSnack('Caller profile data not found', isError: true);
                                  return;
                                }

                                // 5. Define onCallUser callback
                                Future<void> onCallUser(Map<String, dynamic> profile, {required bool isVideoCall}) async {
                                  await _initiateSpoofedCall(
                                    {
                                      'uid': seedUid,
                                      'name': seedName,
                                    },
                                    profile,
                                    isVideo: isVideoCall,
                                  );
                                }

                                // 6. Push chat screen
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        currentUser: AppUser(
                                          uid: seedUid,
                                          displayName: seedName,
                                          email: 'admin_seed@example.com',
                                          isSeed: true,
                                        ),
                                        targetProfile: targetProfile,
                                        onCallUser: onCallUser,
                                      ),
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCall ? const Color(0xFF00C9A7) : const Color(0xFF6C63FF),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: Icon(
                                isCall ? Icons.phone_callback_rounded : Icons.chat_bubble_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                              label: Text(
                                isCall ? 'Answer/Call' : 'Reply',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Action: Dismiss Alert
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                if (isCall) {
                                  final alertId = alert['id']?.toString() ?? '';
                                  if (alertId.isNotEmpty) {
                                    await UserService.deleteCallAlert(seedUid, alertId);
                                  }
                                } else {
                                  // For message conversations, we delete the conversation node to clear the alert
                                  await FirebaseDatabase.instance
                                      .ref('conversations/$seedUid/$callerId')
                                      .remove();
                                }
                                _showSnack('Alert dismissed', isError: false);
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
      },
    );
  }
}
