import 'package:flutter/material.dart';
import 'package:chating/models/app_user.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/screens/profile_setup_screen.dart';

class GenderSelectionScreen extends StatefulWidget {
  final AppUser user;
  const GenderSelectionScreen({super.key, required this.user});

  @override
  State<GenderSelectionScreen> createState() => _GenderSelectionScreenState();
}

class _GenderSelectionScreenState extends State<GenderSelectionScreen>
    with TickerProviderStateMixin {
  String? _selected; // 'male' or 'female'
  bool _saving = false;

  late final AnimationController _pulseController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_selected == null) return;
    setState(() => _saving = true);

    await UserService.saveProfile(user: widget.user, gender: _selected!);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, a, __) => ProfileSetupScreen(
          user: widget.user,
          initialGender: _selected!,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
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
            colors: [Color(0xFF0f0c29), Color(0xFF302b63), Color(0xFF24243e)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  _buildHeader(),
                  const SizedBox(height: 48),
                  _buildCards(),
                  const Spacer(),
                  _buildConfirmButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundImage: widget.user.photoURL != null
              ? NetworkImage(widget.user.photoURL!)
              : null,
          backgroundColor: const Color(0xFF6C63FF),
          child: widget.user.photoURL == null
              ? Text(
                  (widget.user.displayName != null && widget.user.displayName!.isNotEmpty) ? widget.user.displayName![0].toUpperCase() : 'U',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                )
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          'Hey, ${widget.user.displayName?.split(' ').first ?? 'there'} 👋',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'I am a...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose your gender to see the right profiles',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9090B0), fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildCards() {
    return Row(
      children: [
        Expanded(
          child: _GenderCard(
            gender: 'male',
            label: 'Male',
            emoji: '👨',
            selectedColor: const Color(0xFF4F8EF7),
            gradientColors: const [Color(0xFF1B3A6B), Color(0xFF0D2137)],
            isSelected: _selected == 'male',
            pulseController: _pulseController,
            onTap: () => setState(() => _selected = 'male'),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _GenderCard(
            gender: 'female',
            label: 'Female',
            emoji: '👩',
            selectedColor: const Color(0xFFE91E8C),
            gradientColors: const [Color(0xFF6B1B45), Color(0xFF370D25)],
            isSelected: _selected == 'female',
            pulseController: _pulseController,
            onTap: () => setState(() => _selected = 'female'),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmButton() {
    final isReady = _selected != null && !_saving;
    return AnimatedOpacity(
      opacity: _selected != null ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 300),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          onPressed: isReady ? _confirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            disabledBackgroundColor: const Color(0xFF6C63FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: isReady ? 8 : 0,
            shadowColor: const Color(0xFF6C63FF).withOpacity(0.5),
          ),
          child: _saving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 20),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GenderCard extends StatelessWidget {
  final String gender;
  final String label;
  final String emoji;
  final Color selectedColor;
  final List<Color> gradientColors;
  final bool isSelected;
  final AnimationController pulseController;
  final VoidCallback onTap;

  const _GenderCard({
    required this.gender,
    required this.label,
    required this.emoji,
    required this.selectedColor,
    required this.gradientColors,
    required this.isSelected,
    required this.pulseController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        height: 200,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [
                    selectedColor.withOpacity(0.9),
                    selectedColor.withOpacity(0.5),
                  ]
                : gradientColors,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? selectedColor : Colors.white12,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedColor.withOpacity(0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  )
                ]
              : [],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(fontSize: isSelected ? 64 : 52),
                  child: Text(emoji),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    shadows: isSelected
                        ? [
                            Shadow(
                              color: selectedColor,
                              blurRadius: 12,
                            )
                          ]
                        : [],
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned(
                top: 14,
                right: 14,
                child: AnimatedBuilder(
                  animation: pulseController,
                  builder: (_, __) => Transform.scale(
                    scale: 0.9 + pulseController.value * 0.1,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: selectedColor.withOpacity(0.6),
                            blurRadius: 8,
                          )
                        ],
                      ),
                      child: Icon(Icons.check_rounded,
                          color: selectedColor, size: 18),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
