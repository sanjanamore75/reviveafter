import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:chating/services/zego_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } catch (e) {
      print('Email Sign-In Error: $e');
      return null;
    }
  }

  Future<User?> registerWithEmailAndPassword(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } catch (e) {
      print('Email Registration Error: $e');
      return null;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      print('Google Sign-In Error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    ZegoService().uninit();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Automatically signs in or creates a user based on the device's unique ID.
  Future<User?> getOrCreateDeviceUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedUid = prefs.getString('device_user_uid');

      if (savedUid != null && _auth.currentUser != null && _auth.currentUser!.uid == savedUid) {
        return _auth.currentUser;
      }

      // If we have a saved UID but current user is null (or different), try to use it?
      // Firebase anonymous users persist until sign out or data clear.
      if (_auth.currentUser != null) {
        await prefs.setString('device_user_uid', _auth.currentUser!.uid);
        return _auth.currentUser;
      }

      // Perform anonymous sign in
      final result = await _auth.signInAnonymously();
      final user = result.user;

      if (user != null) {
        await prefs.setString('device_user_uid', user.uid);
        return user;
      }
    } catch (e) {
      print('Device Auto-Login Error: $e');
    }
    return null;
  }
}
