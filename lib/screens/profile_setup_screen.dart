import 'dart:io';
import 'package:flutter/material.dart';
import 'package:chating/models/app_user.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:chating/services/user_service.dart';
import 'package:chating/screens/home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final AppUser user;
  final String initialGender;

  const ProfileSetupScreen({
    super.key,
    required this.user,
    required this.initialGender,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late String _gender;
  late String _lookingFor;
  
  File? _profileImage;
  bool _isSaving = false;
  final ImagePicker _picker = ImagePicker();

  // CLOUDINARY CONFIG
  // TODO: Replace with your actual Cloud Name
  final String _cloudName = 'dlcxmgupv'; 
  final String _uploadPreset = 'chat_preset';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.displayName ?? '');
    _phoneController = TextEditingController();
    _gender = widget.initialGender;
    _lookingFor = widget.initialGender == 'male' ? 'female' : 'male';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image != null) {
      setState(() => _profileImage = File(image.path));
    }
  }

  Future<bool> _verifyFace(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final faceDetector = FaceDetector(options: FaceDetectorOptions());
    try {
      final List<Face> faces = await faceDetector.processImage(inputImage);
      return faces.isNotEmpty;
    } finally {
      await faceDetector.close();
    }
  }

  Future<String?> _uploadToCloudinary(File file) async {
    try {
      final cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);
      CloudinaryResponse response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(file.path, resourceType: CloudinaryResourceType.Image),
      );
      return response.secureUrl;
    } catch (e) {
      print('Cloudinary error: $e');
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      String? photoURL;

      if (_profileImage != null) {
        // 1. Verify Face
        final hasFace = await _verifyFace(_profileImage!);
        if (!hasFace) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Upload correct image: No face detected in the picture.'),
                backgroundColor: Colors.orangeAccent,
              ),
            );
          }
          setState(() => _isSaving = false);
          return;
        }

        // 2. Upload to Cloudinary
        photoURL = await _uploadToCloudinary(_profileImage!);
        if (photoURL == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to upload image. Please check your Cloudinary config.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          setState(() => _isSaving = false);
          return;
        }
      }

      // 3. Save to Firebase
      await UserService.saveProfile(
        user: widget.user,
        gender: _gender,
        name: _nameController.text.trim(),
        lookingFor: _lookingFor,
        phone: _phoneController.text.trim(),
      );

      // If we have a photo, update the photoURL separately or in saveProfile
      if (photoURL != null) {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(photoURL);
        // Also update in DB
        final ref = UserService.getUserRef(widget.user);
        await ref.update({'photoURL': photoURL});
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            user: widget.user,
            myGender: _gender,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Complete Your Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tell us more about yourself to get started',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 30),

                  // Profile Picture Upload
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _pickImage,
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.white.withOpacity(0.1),
                            backgroundImage: _profileImage != null 
                                ? FileImage(_profileImage!) 
                                : (widget.user.photoURL != null ? NetworkImage(widget.user.photoURL!) : null) as ImageProvider?,
                            child: (_profileImage == null && widget.user.photoURL == null)
                                ? const Icon(Icons.add_a_photo_rounded, size: 40, color: Color(0xFF6C63FF))
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Color(0xFF6C63FF), shape: BoxShape.circle),
                            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'If you upload an image then only your profile\nwill be visible to others.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFFFB74D), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Name Input
                  _buildLabel('Display Name'),
                  _buildTextField(
                    controller: _nameController,
                    hint: 'Your name',
                    icon: Icons.person_rounded,
                    validator: (val) => val == null || val.isEmpty ? 'Please enter your name' : null,
                  ),
                  const SizedBox(height: 20),

                  // Gender Input
                  _buildLabel('I am a'),
                  _buildDropdown(
                    value: _gender,
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('♂ Male')),
                      DropdownMenuItem(value: 'female', child: Text('♀ Female')),
                    ],
                    onChanged: (val) => setState(() => _gender = val!),
                  ),
                  const SizedBox(height: 20),

                  // Looking For Input
                  _buildLabel('I am looking for'),
                  _buildDropdown(
                    value: _lookingFor,
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('👩 Females')),
                      DropdownMenuItem(value: 'male', child: Text('👨 Males')),
                      DropdownMenuItem(value: 'both', child: Text('🌈 Everyone')),
                    ],
                    onChanged: (val) => setState(() => _lookingFor = val!),
                  ),
                  const SizedBox(height: 20),

                  // Phone Input
                  _buildLabel('Phone Number'),
                  _buildTextField(
                    controller: _phoneController,
                    hint: '+1 234 567 890',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    validator: (val) => val == null || val.isEmpty ? 'Please enter your phone number' : null,
                  ),
                  const SizedBox(height: 40),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 8,
                        shadowColor: const Color(0xFF6C63FF).withOpacity(0.5),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Finish Setup',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: const Color(0xFF16213e),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6C63FF)),
          isExpanded: true,
        ),
      ),
    );
  }
}
