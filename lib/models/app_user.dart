import 'package:firebase_auth/firebase_auth.dart';

class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String? photoURL;
  final bool isSeed;

  AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoURL,
    this.isSeed = false,
  });

  factory AppUser.fromFirebaseUser(User user) {
    return AppUser(
      uid: user.uid,
      displayName: user.displayName ?? 'User',
      email: user.email ?? '',
      photoURL: user.photoURL,
      isSeed: false,
    );
  }

  factory AppUser.fromSeedProfile(Map<String, dynamic> data) {
    return AppUser(
      uid: data['uid'] ?? '',
      displayName: data['name'] ?? 'User',
      email: data['email'] ?? 'admin_seed@example.com',
      photoURL: data['photoURL'] as String?,
      isSeed: true,
    );
  }
}
