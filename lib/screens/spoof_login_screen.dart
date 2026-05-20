import 'package:flutter/material.dart';
import 'package:chating/services/auth_service.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/models/app_user.dart';
import 'package:chating/screens/home_screen.dart';

class SpoofLoginScreen extends StatefulWidget {
  const SpoofLoginScreen({super.key});

  @override
  State<SpoofLoginScreen> createState() => _SpoofLoginScreenState();
}

class _SpoofLoginScreenState extends State<SpoofLoginScreen> {
  final TextEditingController _uidController = TextEditingController();
  bool _isLoading = false;

  Future<void> _loginAsPushedProfile() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) {
      _showSnack('Please enter a UID');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final AppUser mockUser = AppUser(uid: uid, displayName: 'User', email: 'admin_seed@example.com');
      final profile = await UserService.getUserData(mockUser);
      
      if (profile == null) {
        _showSnack('Profile not found for UID: $uid');
        return;
      }

      // Check if it's actually a seed profile
      if (profile['isSeed'] != true && profile['isSeed'] != 'true') {
        _showSnack('This UID is not a pushed/seed profile.');
        return;
      }

      final appUser = AppUser.fromSeedProfile(profile);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              user: appUser,
              myGender: profile['gender'],
              lookingFor: profile['lookingFor'],
            ),
          ),
        );
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Admin Spoof Login', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF16213e),
        actions: [
          IconButton(
            onPressed: () => AuthService().signOut(),
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFFF6B6B)),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings_rounded, size: 64, color: Color(0xFFFFB74D)),
                const SizedBox(height: 16),
                const Text(
                  'Act as a Pushed Profile',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the UID of a pushed profile to login and view their messages and calls as a normal user.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _uidController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter Pushed Profile UID...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _loginAsPushedProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Login as Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
