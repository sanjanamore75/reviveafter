import 'package:flutter/material.dart';
import 'package:chating/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/models/app_user.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleDeviceLogin() async {
    setState(() => _isLoading = true);
    final user = await _authService.getOrCreateDeviceUser();
    if (mounted) {
      setState(() => _isLoading = false);
      if (user == null) {
        _showSnack('Device login failed. Please try again.');
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    final user = await _authService.signInWithGoogle();
    if (mounted) {
      setState(() => _isLoading = false);
      if (user == null) {
        _showSnack('Sign-in cancelled or failed. Please try again.');
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _showSpoofLoginDialog() {
    final uidController = TextEditingController();
    final passController = TextEditingController();
    bool dialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Login to Account', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: uidController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Account UID',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: dialogLoading ? null : () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: dialogLoading
                    ? null
                    : () async {
                        final uid = uidController.text.trim();
                        final pass = passController.text.trim();

                        if (uid.isEmpty || pass.isEmpty) {
                          _showSnack('Please enter UID and Password');
                          return;
                        }

                        if (pass != 'Krisna@9a') {
                          _showSnack('Invalid password');
                          return;
                        }

                        setDialogState(() => dialogLoading = true);

                        try {
                          final mockUser = AppUser(uid: uid, displayName: 'User', email: 'admin_seed@example.com');
                          final profile = await UserService.getUserData(mockUser);

                          if (profile == null || (profile['isSeed'] != true && profile['isSeed'] != 'true')) {
                            _showSnack('Invalid Account UID');
                            setDialogState(() => dialogLoading = false);
                            return;
                          }

                          // Valid seed profile! 
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('spoofed_uid', uid);

                          // Sign in anonymously to trigger main.dart auth state change
                          await FirebaseAuth.instance.signInAnonymously();

                          if (mounted) {
                            Navigator.pop(context); // Close dialog
                          }
                        } catch (e) {
                          _showSnack('Error: $e');
                          setDialogState(() => dialogLoading = false);
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
                child: dialogLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Login', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF3f3d56)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.video_call_rounded,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // App Name
                      const Text(
                        'ZegoChat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome!\nPlease select a login method to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFB0B0B0),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 60),

                      // Login Buttons
                      if (_isLoading)
                        const CircularProgressIndicator(color: Color(0xFF6C63FF))
                      else ...[
                        // Device Login Button
                        _buildLoginButton(
                          title: 'Quick Device Login',
                          icon: Icons.phonelink_setup_rounded,
                          onTap: _handleDeviceLogin,
                          isPrimary: true,
                        ),
                        const SizedBox(height: 20),

                        // Google Sign-In Button
                        _buildGoogleLoginButton(),
                      ],

                      const SizedBox(height: 40),
                      const Text(
                        'By continuing, you agree to our Terms & Privacy Policy',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _showSpoofLoginDialog,
                        child: const Text(
                          'Already have an account? Login here',
                          style: TextStyle(
                            color: Color(0xFF6C63FF),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.05),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isPrimary ? BorderSide.none : BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          elevation: isPrimary ? 8 : 0,
          shadowColor: isPrimary ? const Color(0xFF6C63FF).withOpacity(0.4) : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleLoginButton() {
    return GestureDetector(
      onTap: _handleGoogleSignIn,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network(
              'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
              height: 24,
              width: 24,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.account_circle,
                color: Colors.white70,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Continue with Google',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
