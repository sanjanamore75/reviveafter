import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chating/models/app_user.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:chating/services/auth_service.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/services/zego_service.dart';
import 'package:chating/services/permission_service.dart';
import 'package:chating/services/zim_service.dart';
import 'package:chating/screens/user_profile_screen.dart';
import 'package:chating/screens/messages_screen.dart';
import 'package:chating/screens/chat_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppUser user;
  final String? myGender; // 'male' or 'female'
  final String? lookingFor; // 'male', 'female', or 'both'
  const HomeScreen({super.key, required this.user, this.myGender, this.lookingFor});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _zegoInitialized = false;
  bool _isCalling = false;
  bool _permissionsGranted = true;
  String _searchText = '';
  int _currentIndex = 0;
  late String _currentInterest;

  /// The preference for profiles we want to display.
  /// The preference for profiles we want to display.
  String get _preference => _currentInterest;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _initZego();
    _currentInterest = widget.lookingFor ?? (widget.myGender == 'male' ? 'female' : 'male');
    _searchController.addListener(
        () => setState(() => _searchText = _searchController.text.trim()));
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
    await ZegoService().init(
      userID: widget.user.uid,
      userName: widget.user.displayName ?? 'User',
    );
    // Also initialize ZIM (In-App Chat) for this user
    await ZimService().init(
      userID: widget.user.uid,
      userName: widget.user.displayName ?? 'User',
    );
    // ✅ Give the signaling plugin 2 seconds to fully connect before enabling calls
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _zegoInitialized = true);
  }

  @override
  void dispose() {
    // We don't uninit here to keep Zego alive for background notifications
    _searchController.dispose();
    super.dispose();
  }


  Future<void> _callUser(Map<String, dynamic> profile,
      {required bool isVideoCall}) async {
    final isSeed = profile['isSeed'] == true || profile['isSeed'] == 'true';
    final targetUid = profile['uid'];

    print('DEBUG: Attempting call to ${profile['name']} (UID: $targetUid, isSeed: $isSeed)');

    if (!_zegoInitialized) {
      print('DEBUG: Zego not initialized yet');
      _showSnack('Still connecting, please wait...', isError: true);
      return;
    }
    setState(() => _isCalling = true);

    try {
      List<ZegoCallUser> invitees = [];

      if (isSeed &&
          profile['adminUid'] != null &&
          profile['adminUid'].toString().isNotEmpty) {
        final adminId = profile['adminUid'].toString();
        print('DEBUG: Calling Admin UID: $adminId for seed profile');
        // Ring only the specific admin who created this profile
        invitees = [
          ZegoCallUser(adminId, profile['name'] ?? 'Admin')
        ];
      } else {
        print('DEBUG: Calling regular User UID: $targetUid');
        // Normal 1-on-1 call for real users or fallback
        invitees = [
          ZegoCallUser(targetUid.toString(), profile['name'] ?? 'User')
        ];
      }

      if (invitees.isEmpty || invitees.first.id.isEmpty) {
        print('DEBUG: Error - Invitee list is empty or ID is missing');
        _showSnack('Invalid target user', isError: true);
        return;
      }

      // ✅ Create call alerts for all invitees
      final Map<String, String> alertIds = {};
      for (var invitee in invitees) {
        final alertId = await UserService.saveCallAlert(
          targetUid: invitee.id,
          callerId: widget.user.uid,
          callerName: widget.user.displayName ?? 'User',
          callerPhoto: widget.user.photoURL,
          isVideo: isVideoCall,
          status: 'missed', 
        );
        if (alertId != null) alertIds[invitee.id] = alertId;
      }

      print('📣 Sending call invitation to: ${invitees.map((u) => u.id).toList()} with resourceID: zego_call');
      final result = await ZegoUIKitPrebuiltCallInvitationService().send(
        invitees: invitees,
        isVideoCall: isVideoCall,
        resourceID: 'zego_call',
        timeoutSeconds: 60,
      );

      print('DEBUG: Call Invitation Send Result: $result');

      // If invitation failed (likely user is offline), update alert status
      if (!result) {
        for (var entry in alertIds.entries) {
          await UserService.updateCallAlertStatus(entry.key, entry.value, 'offline');
        }
      }

      if (!result && mounted) {
        _showSnack('${profile['name']} is offline or unavailable',
            isError: true);
      }
    } catch (e) {
      print('DEBUG: Exception in _callUser: $e');
      if (mounted) _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isCalling = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : const Color(0xFF00C9A7),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBody() {
    if (_currentIndex == 1) {
      return MessagesScreen(
        currentUser: widget.user,
        onCallUser: _callUser,
      );
    }

    if (_currentIndex == 2) {
      return StreamBuilder<Map<String, dynamic>?>(
        stream: UserService.userStream(widget.user),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final coins = profile?['coins'] ?? 0;
          final name = profile?['name'] ?? widget.user.displayName ?? 'User';
          final email = profile?['email'] ?? widget.user.email ?? '';
          final photoURL = profile?['photoURL'] ?? widget.user.photoURL;

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // Profile Section
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: const Color(0xFF6C63FF).withOpacity(0.1),
                          backgroundImage: photoURL != null ? NetworkImage(photoURL) : null,
                          child: photoURL == null
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 32, color: Color(0xFF6C63FF), fontWeight: FontWeight.bold))
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        Text(email, style: const TextStyle(color: Colors.white54, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Wallet Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF4F8EF7)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Current Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
                            Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 32),
                            const SizedBox(width: 12),
                            Text('$coins', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            const Text('Coins', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Coin Packages
                  const Text('Get More Coins', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildCoinPackage(
                    coins: 100,
                    price: '₹99.00',
                    icon: '🥉',
                    color: Colors.brown,
                  ),
                  _buildCoinPackage(
                    coins: 500,
                    price: '₹449.00',
                    icon: '🥈',
                    color: Colors.grey,
                    isBestValue: true,
                  ),
                  _buildCoinPackage(
                    coins: 1000,
                    price: '₹799.00',
                    icon: '🥇',
                    color: Colors.amber,
                  ),
                  _buildCoinPackage(
                    coins: 5000,
                    price: '₹3,499.00',
                    icon: '💎',
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(height: 32),

                  // Background Call Setup
                  const Text('System Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'To receive calls while the app is closed, please ensure "Auto-start" is enabled and "Battery Optimization" is disabled.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => PermissionService.requestAllPermissions(),
                            icon: const Icon(Icons.settings_suggest_rounded),
                            label: const Text('Enable Background Calls'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      );
    }

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
          children: [
            if (!_permissionsGranted) _buildPermissionBanner(),
            _buildHeader(),
            _buildSearchBar(),
            Expanded(child: _buildProfileList()),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(
                  icon: Icons.favorite_rounded, label: 'Profiles', index: 0),
              _buildNavItem(
                  icon: Icons.message_rounded, label: 'Messages', index: 1),
              _buildNavItem(
                  icon: Icons.person_rounded, label: 'My Profile', index: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      {required IconData icon, required String label, required int index}) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? const Color(0xFF6C63FF) : Colors.white54;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    isSelected ? color.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.amber.withOpacity(0.9),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.black87),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Permissions required for background calls',
              style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: _requestPermissions,
            style: TextButton.styleFrom(
              backgroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Grant All', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final user = widget.user;
    final genderLabel = widget.myGender == 'male' ? '♂ Male' : '♀ Female';
    String showingLabel = '';
    Color showingColor = const Color(0xFF6C63FF);

    if (_preference == 'female') {
      showingLabel = 'Showing Female Profiles';
      showingColor = const Color(0xFFE91E8C);
    } else if (_preference == 'male') {
      showingLabel = 'Showing Male Profiles';
      showingColor = const Color(0xFF4F8EF7);
    } else {
      showingLabel = 'Showing Everyone';
      showingColor = const Color(0xFF00C9A7);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border:
            Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage:
                user.photoURL != null ? NetworkImage(user.photoURL!) : null,
            backgroundColor: const Color(0xFF6C63FF),
            child: user.photoURL == null
                ? Text(
                    (user.displayName != null && user.displayName!.isNotEmpty) ? user.displayName![0].toUpperCase() : 'U',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      user.displayName ?? 'User',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(genderLabel,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                  Text(
                    showingLabel,
                    style: TextStyle(color: showingColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Interest Selector
            _buildInterestSelector(showingColor),
            // My ID button
          IconButton(
            onPressed: _showMyIdDialog,
            icon: const Icon(Icons.badge_rounded,
                color: Color(0xFF6C63FF), size: 24),
            tooltip: 'My ID',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search by name...',
            hintStyle: TextStyle(color: Color(0xFF666666)),
            prefixIcon:
                Icon(Icons.search_rounded, color: Color(0xFF6C63FF), size: 22),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: UserService.profilesByPreference(
        lookingFor: _preference,
        excludeUID: widget.user.uid,
        onlyRealUsers: widget.user.isSeed,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
        }

        final profiles = (snapshot.data ?? []).where((p) {
          if (_searchText.isEmpty) return true;
          final name = (p['name'] ?? '').toString().toLowerCase();
          return name.contains(_searchText.toLowerCase());
        }).toList();

        if (profiles.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final profile = profiles[index];
            return _ProfileCard(
              profile: profile,
              isCallingAny: _isCalling,
              isZegoReady: _zegoInitialized,
              onVideoCall: () => _callUser(profile, isVideoCall: true),
              onVoiceCall: () => _callUser(profile, isVideoCall: false),
              onCopyId: () {
                Clipboard.setData(ClipboardData(text: profile['uid'] ?? ''));
                _showSnack('ID copied!');
              },
              onTap: () async {
                // Save conversation record
                await UserService.saveConversation(
                  myUID: widget.user.uid,
                  targetProfile: profile,
                );
                if (!mounted) return;
                // Navigate to ChatScreen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      currentUser: widget.user,
                      targetProfile: profile,
                      onCallUser: _callUser,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final label = _preference == 'both' ? 'users' : (_preference == 'female' ? 'female' : 'male');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _preference == 'both' ? '👥' : (_preference == 'female' ? '👩' : '👨'),
            style: const TextStyle(fontSize: 64),
          ),
          const SizedBox(height: 16),
          Text(
            'No $label profiles yet',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask $label to sign up!',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinPackage({
    required int coins,
    required String price,
    required String icon,
    required Color color,
    bool isBestValue = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isBestValue ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(icon, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$coins Coins', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                if (isBestValue)
                  const Text('Best Value', style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _buyCoins(coins, price),
            style: ElevatedButton.styleFrom(
              backgroundColor: isBestValue ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(price),
          ),
        ],
      ),
    );
  }

  void _buyCoins(int amount, String price) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Confirm Purchase', style: TextStyle(color: Colors.white)),
        content: Text('Do you want to buy $amount coins for $price?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showSnack('Processing payment...');
              await UserService.addCoins(widget.user, amount);
              _showSnack('Successfully added $amount coins!', isError: false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            child: const Text('Buy Now'),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final isVideo = alert['isVideo'] == true;
    final timestamp = alert['timestamp'] as int? ?? 0;
    final timeStr = _formatTimestamp(timestamp);
    final photoURL = alert['callerPhoto'] as String?;
    final name = alert['callerName'] ?? 'User';
    final callerId = alert['callerId'] ?? '';
    final status = alert['status'] ?? 'missed';
    final isOffline = status == 'offline';

    return GestureDetector(
      onTap: () async {
        final action = await Navigator.push<String?>(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              targetUser: {
                'uid': callerId,
                'name': name,
                'photoURL': photoURL,
              },
              currentUser: widget.user,
            ),
          ),
        );

        if (action == 'video') {
          _callUser({
            'uid': callerId,
            'name': name,
            'photoURL': photoURL,
          }, isVideoCall: true);
        } else if (action == 'voice') {
          _callUser({
            'uid': callerId,
            'name': name,
            'photoURL': photoURL,
          }, isVideoCall: false);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isOffline ? Colors.redAccent.withOpacity(0.05) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isOffline ? Colors.redAccent.withOpacity(0.2) : Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: (photoURL != null && photoURL.isNotEmpty) ? NetworkImage(photoURL) : null,
              backgroundColor: const Color(0xFF6C63FF).withOpacity(0.1),
              child: (photoURL == null || photoURL.isEmpty)
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      if (isOffline) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
                          child: const Text('OFFLINE', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded, color: isOffline ? Colors.redAccent.withOpacity(0.5) : Colors.white38, size: 14),
                      const SizedBox(width: 4),
                      Text(isVideo ? 'Video call' : 'Voice call', style: TextStyle(color: isOffline ? Colors.redAccent.withOpacity(0.5) : Colors.white38, fontSize: 12)),
                      const SizedBox(width: 8),
                      const Text('•', style: TextStyle(color: Colors.white24, fontSize: 12)),
                      const SizedBox(width: 8),
                      Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => UserService.deleteCallAlert(widget.user.uid, alert['id']),
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white24, size: 20),
            ),
            IconButton(
              onPressed: () {
                // Trigger a call back
                _callUser({
                  'uid': callerId,
                  'name': name,
                  'photoURL': photoURL,
                }, isVideoCall: isVideo);
              },
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: (isOffline ? Colors.redAccent : const Color(0xFF6C63FF)).withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded, color: isOffline ? Colors.redAccent : const Color(0xFF6C63FF), size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${date.day}/${date.month}';
  }

  Widget _buildInterestSelector(Color activeColor) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        setState(() => _currentInterest = value);
        // Optionally save to DB here if you want it to persist across sessions
        final user = widget.user;
        if (!user.isSeed) {
          UserService.getUserRef(user).update({'lookingFor': value});
        }
      },
      icon: Icon(Icons.filter_list_rounded, color: activeColor, size: 24),
      tooltip: 'Change Interest',
      color: const Color(0xFF1E1E2E),
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        _buildInterestItem('female', '👩 Females', const Color(0xFFE91E8C)),
        _buildInterestItem('male', '👨 Males', const Color(0xFF4F8EF7)),
        _buildInterestItem('both', '🌈 Everyone', const Color(0xFF00C9A7)),
      ],
    );
  }

  PopupMenuItem<String> _buildInterestItem(String value, String label, Color color) {
    final isSelected = _currentInterest == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Text(label, style: TextStyle(color: isSelected ? color : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check_circle_rounded, color: color, size: 16),
          ],
        ],
      ),
    );
  }

  void _showMyIdDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.badge_rounded, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text('Your User ID',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                widget.user.uid,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Share this ID so others can call you',
              style: TextStyle(color: Color(0xFF888888), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.user.uid));
              Navigator.pop(context);
              _showSnack('ID copied to clipboard!');
            },
            icon: const Icon(Icons.copy_rounded,
                color: Color(0xFF6C63FF), size: 18),
            label: const Text('Copy ID',
                style: TextStyle(color: Color(0xFF6C63FF))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}

// ─── Profile Card ─────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final bool isCallingAny;
  final bool isZegoReady;
  final VoidCallback onVideoCall;
  final VoidCallback onVoiceCall;
  final VoidCallback onCopyId;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.profile,
    required this.isCallingAny,
    required this.isZegoReady,
    required this.onVideoCall,
    required this.onVoiceCall,
    required this.onCopyId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = profile['name'] ?? 'User';
    final photoURL = profile['photoURL'] as String?;
    final gender = profile['gender'] ?? 'male';
    final genderColor =
        gender == 'female' ? const Color(0xFFE91E8C) : const Color(0xFF4F8EF7);
    final genderIcon = gender == 'female' ? '♀' : '♂';

    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                    ? NetworkImage(photoURL)
                    : null,
                backgroundColor: genderColor.withOpacity(0.3),
                child: (photoURL == null || photoURL.isEmpty)
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: TextStyle(
                            color: genderColor,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: genderColor,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xFF1a1a2e), width: 2),
                  ),
                  child: Center(
                    child: Text(genderIcon,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // Name + ID
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onCopyId,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile['uid'] ?? '',
                          style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 10,
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy_rounded,
                          color: Color(0xFF555555), size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Call buttons
          Column(
            children: [
              _MiniCallBtn(
                icon: Icons.videocam_rounded,
                color: const Color(0xFF6C63FF),
                onTap: (isCallingAny || !isZegoReady) ? null : onVideoCall,
              ),
              const SizedBox(height: 8),
              _MiniCallBtn(
                icon: Icons.call_rounded,
                color: const Color(0xFF00C9A7),
                onTap: (isCallingAny || !isZegoReady) ? null : onVoiceCall,
              ),
            ],
          ),
        ],
      ),
    ));
  }
}

class _MiniCallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MiniCallBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color:
              enabled ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: enabled ? color.withOpacity(0.5) : Colors.white12),
        ),
        child: Icon(
          icon,
          color: enabled ? color : Colors.white24,
          size: 20,
        ),
      ),
    );
  }
}
