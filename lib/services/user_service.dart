import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static final _db = FirebaseDatabase.instance;

  /// Returns the DatabaseReference for [user].
  static DatabaseReference getUserRef(User user) =>
      _db.ref('users/${user.uid}');

  /// Saves the user's profile to Firebase.
  static Future<void> saveProfile({
    required User user,
    required String gender,
    String? name,
    String? lookingFor,
    String? phone,
    String? photoURL,
  }) async {
    final ref = getUserRef(user);
    final snap = await ref.child('coins').get();

    // Initialize coins to 50 if it's a new profile or missing
    int currentCoins = 50;
    if (snap.exists) {
      currentCoins = int.tryParse(snap.value.toString()) ?? 50;
    }

    await ref.update({
      'uid': user.uid,
      'name': name ?? user.displayName ?? 'User',
      'email': user.email ?? '',
      'photoURL': photoURL ?? user.photoURL ?? '',
      'gender': gender,
      'lookingFor': lookingFor ?? (gender == 'male' ? 'female' : 'male'),
      'phone': phone ?? '',
      'coins': currentCoins,
      'createdAt': ServerValue.timestamp,
    });
  }

  /// Updates the user's FCM token.
  static Future<void> updateUserToken(String uid, String token) async {
    await _db.ref('users/$uid').update({'fcmToken': token});
  }

  /// Returns a stream of the current user's profile data.
  static Stream<Map<String, dynamic>?> userStream(User user) {
    return getUserRef(user).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return null;
      return Map<String, dynamic>.from(data);
    });
  }

  /// Adds [amount] to the user's coin balance.
  static Future<void> addCoins(User user, int amount) async {
    final ref = getUserRef(user);
    final snap = await ref.child('coins').get();
    int current = 0;
    if (snap.exists) {
      current = int.tryParse(snap.value.toString()) ?? 0;
    }
    await ref.update({'coins': current + amount});
  }

  /// Returns the full user data.
  static Future<Map<String, dynamic>?> getUserData(User user) async {
    try {
      final snap = await getUserRef(user).get().timeout(const Duration(seconds: 5));
      if (!snap.exists || snap.value == null) return null;
      
      if (snap.value is Map) {
        return Map<String, dynamic>.from(snap.value as Map);
      }
      return null;
    } catch (e) {
      print('❌ Error fetching user data: $e');
      // Rethrow to allow the FutureBuilder to catch and show the ErrorScreen
      rethrow;
    }
  }

  /// Returns the saved gender for [user], or null if not set yet.
  static Future<String?> getGender(User user) async {
    final snap = await getUserRef(user).get();
    if (!snap.exists) return null;
    final data = snap.value as Map<dynamic, dynamic>?;
    return data?['gender'] as String?;
  }

  /// Returns a stream of profiles based on the user's preference [lookingFor].
  /// [lookingFor] can be 'male', 'female', or 'both'.
  static Stream<List<Map<String, dynamic>>> profilesByPreference({
    required String lookingFor,
    required String excludeUID,
  }) {
    return _db.ref('users').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];

      return data.values
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((user) {
        // 1. Exclude self
        if (user['uid'] == excludeUID) return false;

        // 2. Must have a photo
        if (user['photoURL'] == null || user['photoURL'].toString().isEmpty) {
          return false;
        }

        // 3. Match gender preference
        final gender = user['gender'] as String?;
        if (lookingFor == 'both') {
          return gender == 'male' || gender == 'female';
        }
        return gender == lookingFor;
      }).toList();
    });
  }

  // ─── ADMIN METHODS ────────────────────────────────────────────────────────

  /// Returns a list of all admin UIDs.
  static Future<List<String>> getAdminUids() async {
    final snap = await _db.ref('users').get();
    if (!snap.exists) return [];
    final data = snap.value as Map<dynamic, dynamic>?;
    if (data == null) return [];

    final adminEmails = ['analystcodehub@gmail.com', 'chatzego@gmail.com'];
    final List<String> adminUids = [];

    for (var entry in data.values) {
      if (entry is Map) {
        final email = entry['email']?.toString();
        final uid = entry['uid']?.toString();
        if (email != null && adminEmails.contains(email) && uid != null) {
          adminUids.add(uid);
        }
      }
    }
    return adminUids;
  }

  /// Stream of all real users (excluding seeds)
  static Stream<List<Map<String, dynamic>>> realUsersStream() {
    return _db.ref('users').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      return data.values
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((user) => user['isSeed'] != true && user['uid'] != null)
          .toList();
    });
  }

  /// Pushes a fake/seed profile into Firestore.
  static Future<void> addSeedProfile({
    required String name,
    required String gender,
    required String photoURL,
    required String adminUid,
  }) async {
    final docRef = _db.ref('users').push(); // Auto-generate UID
    await docRef.set({
      'uid': docRef.key,
      'name': name,
      'email': 'admin_seed@example.com',
      'photoURL': photoURL,
      'gender': gender,
      'isSeed': true, // helps the admin identify which profiles were pushed
      'adminUid': adminUid,
      'createdAt': ServerValue.timestamp,
    }).timeout(const Duration(seconds: 10), onTimeout: () {
      throw Exception(
          "Network timeout: Ensure you have an active internet connection.");
    });
  }

  /// Deletes a user profile by UID.
  static Future<void> deleteProfile(String uid) async {
    await _db.ref('users/$uid').remove();
  }

  /// Stream of all seed profiles created by the admin.
  static Stream<List<Map<String, dynamic>>> seedProfilesStream() {
    return _db
        .ref('users')
        .orderByChild('isSeed')
        .equalTo(true)
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      final list =
          data.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      list.sort((a, b) {
        final aTime = a['createdAt'] as int? ?? 0;
        final bTime = b['createdAt'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
      return list;
    });
  }

  /// Saves a call alert for the [targetUid].
  static Future<String?> saveCallAlert({
    required String targetUid,
    required String callerId,
    required String callerName,
    required String? callerPhoto,
    required bool isVideo,
    String status = 'missed',
  }) async {
    final ref = _db.ref('call_alerts/$targetUid').push();
    await ref.set({
      'id': ref.key,
      'callerId': callerId,
      'callerName': callerName,
      'callerPhoto': callerPhoto ?? '',
      'isVideo': isVideo,
      'status': status,
      'timestamp': ServerValue.timestamp,
    });
    return ref.key;
  }

  /// Updates the status of a call alert.
  static Future<void> updateCallAlertStatus(
      String targetUid, String alertId, String status) async {
    await _db.ref('call_alerts/$targetUid/$alertId').update({'status': status});
  }

  /// Returns a stream of call alerts for [uid].
  static Stream<List<Map<String, dynamic>>> getCallAlerts(String uid) {
    return _db.ref('call_alerts/$uid').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      final list =
          data.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      list.sort((a, b) {
        final aTime = a['timestamp'] as int? ?? 0;
        final bTime = b['timestamp'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
      return list;
    });
  }

  /// Deletes a specific call alert.
  static Future<void> deleteCallAlert(String uid, String alertId) async {
    await _db.ref('call_alerts/$uid/$alertId').remove();
  }

  // ─── CONVERSATION / MESSAGES METHODS ──────────────────────────────────────

  /// Saves (or updates) a conversation entry for [myUID] with [targetProfile].
  /// Path: conversations/{myUID}/{targetUID}
  static Future<void> saveConversation({
    required String myUID,
    required Map<String, dynamic> targetProfile,
  }) async {
    final targetUID = targetProfile['uid']?.toString() ?? '';
    if (targetUID.isEmpty || targetUID == myUID) return;

    final ref = _db.ref('conversations/$myUID/$targetUID');
    final snap = await ref.get();

    // Only write metadata if not already present (preserve lastMessage)
    if (!snap.exists) {
      await ref.set({
        'uid': targetUID,
        'name': targetProfile['name'] ?? 'User',
        'photoURL': targetProfile['photoURL'] ?? '',
        'lastMessage': '',
        'lastMessageTime': ServerValue.timestamp,
        'lastActivity': ServerValue.timestamp,
      });
    } else {
      // Update name/photo in case they changed, keep lastMessage intact
      await ref.update({
        'name': targetProfile['name'] ?? 'User',
        'photoURL': targetProfile['photoURL'] ?? '',
        'lastActivity': ServerValue.timestamp,
      });
    }
  }

  /// Returns a real-time stream of all conversations for [myUID],
  /// sorted newest activity first.
  static Stream<List<Map<String, dynamic>>> getConversations(String myUID) {
    return _db.ref('conversations/$myUID').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      final list = data.values
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      list.sort((a, b) {
        final aT = a['lastActivity'] as int? ?? 0;
        final bT = b['lastActivity'] as int? ?? 0;
        return bT.compareTo(aT);
      });
      return list;
    });
  }

  /// Updates the last message preview for a conversation.
  static Future<void> updateConversationLastMessage({
    required String myUID,
    required String targetUID,
    required String message,
  }) async {
    await _db.ref('conversations/$myUID/$targetUID').update({
      'lastMessage': message,
      'lastMessageTime': ServerValue.timestamp,
      'lastActivity': ServerValue.timestamp,
    });
  }

  /// Returns a merged stream of conversations and call alerts for [uid].
  static Stream<List<Map<String, dynamic>>> getUnifiedHistory(String uid) async* {
    List<Map<String, dynamic>> convs = [];
    List<Map<String, dynamic>> calls = [];

    await for (final event in _db.ref('conversations/$uid').onValue) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      convs = data?.values.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      
      // Also get calls
      final callSnap = await _db.ref('call_alerts/$uid').get();
      final callData = callSnap.value as Map<dynamic, dynamic>?;
      calls = callData?.values.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];

      final merged = [...convs, ...calls];
      merged.sort((a, b) {
        final aT = (a['lastActivity'] ?? a['timestamp']) as int? ?? 0;
        final bT = (b['lastActivity'] ?? b['timestamp']) as int? ?? 0;
        return bT.compareTo(aT);
      });
      yield merged;
    }
  }
}

