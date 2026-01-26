import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/user/app_user.dart';

class AuthService {
  static const List<String> _scopes = [
    'email',
    'profile',
    'https://www.googleapis.com/auth/gmail.readonly',
  ];

  // Web Client ID - used by Android for serverClientId
  static const String _webClientId =
      '749462764377-aclvf7ak8dns39fmcd4vi4lof5ggaahe.apps.googleusercontent.com';

  // iOS Client ID
  static const String _iosClientId =
      '749462764377-1ugu6rat3jetoaomu1beeo2koqfmr5ic.apps.googleusercontent.com';

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  late final GoogleSignIn _googleSignIn;

  GoogleSignInAccount? _googleUser;
  AppUser? _appUser;

  AuthService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance {
    _googleSignIn = GoogleSignIn(
      scopes: _scopes,
      clientId: Platform.isIOS ? _iosClientId : null,
      serverClientId: Platform.isAndroid ? _webClientId : null,
      forceCodeForRefreshToken: true,
    );
  }

  // Current Firebase user
  User? get firebaseUser => _firebaseAuth.currentUser;

  // Current app user (from Firestore)
  AppUser? get currentUser => _appUser;

  // Check if user is signed in (with Google, not just anonymous)
  bool get isSignedIn => firebaseUser != null && !firebaseUser!.isAnonymous;

  // Check if user has any auth (including anonymous)
  bool get hasAuth => firebaseUser != null;

  // Check if current user is anonymous
  bool get isAnonymous => firebaseUser?.isAnonymous ?? false;

  // Get user ID
  String? get userId => firebaseUser?.uid;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// Initialize the auth service
  Future<void> init() async {
    debugPrint('[AuthService] Initializing...');

    // Listen for Google Sign-In changes
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      _googleUser = account;
      debugPrint('[AuthService] Google user changed: ${account?.email}');
    });

    // Check current auth state
    if (_firebaseAuth.currentUser != null) {
      final user = _firebaseAuth.currentUser!;

      if (user.isAnonymous) {
        debugPrint('[AuthService] Anonymous user exists: ${user.uid}');
        await _ensureAnonymousUserDocument(user);
      } else {
        debugPrint('[AuthService] Google user exists, loading app user...');
        await _loadAppUser();

        // Try silent Google sign in to restore Gmail access
        await _googleSignIn.signInSilently();
        _googleUser = _googleSignIn.currentUser;
      }
    } else {
      // No user exists, create anonymous account
      debugPrint('[AuthService] No user exists, creating anonymous account...');
      await _signInAnonymously();
    }

    debugPrint('[AuthService] Initialized. Signed in: $isSignedIn, Anonymous: $isAnonymous');
  }

  /// Sign in anonymously (for new users who haven't signed in with Google)
  Future<User?> _signInAnonymously() async {
    try {
      debugPrint('[AuthService] Creating anonymous account...');
      final userCredential = await _firebaseAuth.signInAnonymously();
      final user = userCredential.user;

      if (user != null) {
        debugPrint('[AuthService] Anonymous account created: ${user.uid}');
        await _ensureAnonymousUserDocument(user);
      }

      return user;
    } catch (e) {
      debugPrint('[AuthService] Error creating anonymous account: $e');
      return null;
    }
  }

  /// Ensure anonymous user has a document in Firestore
  Future<void> _ensureAnonymousUserDocument(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    if (!userDoc.exists) {
      debugPrint('[AuthService] Creating anonymous user document...');
      final now = DateTime.now();
      await userRef.set({
        'uid': user.uid,
        'isAnonymous': true,
        'createdAt': Timestamp.fromDate(now),
        'lastLoginAt': Timestamp.fromDate(now),
      });
    }
  }

  /// Sign in with Google and create/update Firebase account
  /// If user was anonymous, attempts to link accounts or migrate data
  Future<AppUser?> signInWithGoogle() async {
    debugPrint('[AuthService] --- Sign In Started ---');

    // Store anonymous user ID for potential data migration
    final wasAnonymous = isAnonymous;
    final anonymousUid = wasAnonymous ? firebaseUser!.uid : null;

    try {
      // Step 1: Google Sign-In
      debugPrint('[AuthService] Starting Google Sign-In...');
      final googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint('[AuthService] Google Sign-In cancelled by user');
        return null;
      }

      _googleUser = googleUser;
      debugPrint('[AuthService] Google Sign-In successful: ${googleUser.email}');

      // Step 2: Get Google auth credentials
      debugPrint('[AuthService] Getting Google auth credentials...');
      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      User? firebaseUser;

      // Step 3: Try to link anonymous account to Google, or sign in directly
      if (wasAnonymous && _firebaseAuth.currentUser != null) {
        debugPrint('[AuthService] Attempting to link anonymous account to Google...');
        try {
          final userCredential = await _firebaseAuth.currentUser!.linkWithCredential(credential);
          firebaseUser = userCredential.user;
          debugPrint('[AuthService] Successfully linked anonymous account to Google: ${firebaseUser?.uid}');
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
            // Google account already exists, need to migrate data
            debugPrint('[AuthService] Google account already exists, migrating data...');

            // Sign in with Google credential (this will switch to the existing account)
            final userCredential = await _firebaseAuth.signInWithCredential(credential);
            firebaseUser = userCredential.user;

            if (firebaseUser != null && anonymousUid != null) {
              // Migrate flights from anonymous account to Google account
              await _migrateFlightsFromAnonymous(anonymousUid, firebaseUser.uid);

              // Delete anonymous user document
              await _deleteAnonymousUserData(anonymousUid);
            }
          } else {
            rethrow;
          }
        }
      } else {
        // No anonymous account, just sign in with Google
        debugPrint('[AuthService] Signing in to Firebase with Google...');
        final userCredential = await _firebaseAuth.signInWithCredential(credential);
        firebaseUser = userCredential.user;
      }

      if (firebaseUser == null) {
        debugPrint('[AuthService] Firebase sign-in failed - no user returned');
        return null;
      }

      debugPrint('[AuthService] Firebase Sign-In successful: ${firebaseUser.uid}');

      // Step 4: Create or update user in Firestore
      debugPrint('[AuthService] Creating/updating user in Firestore...');
      _appUser = await _createOrUpdateUser(firebaseUser, googleUser);

      // Step 5: Store refresh token for backend use (Gmail webhook)
      final serverAuthCode = googleUser.serverAuthCode;
      if (serverAuthCode != null) {
        debugPrint('[AuthService] Storing refresh token...');
        try {
          final callable = _functions.httpsCallable('storeRefreshToken');
          await callable.call({'authCode': serverAuthCode});
          debugPrint('[AuthService] Refresh token stored successfully');

          // Step 6: Set up Gmail watch for push notifications
          debugPrint('[AuthService] Setting up Gmail watch...');
          final watchCallable = _functions.httpsCallable('setupGmailWatch');
          await watchCallable.call();
          debugPrint('[AuthService] Gmail watch set up successfully');
        } catch (e) {
          debugPrint('[AuthService] Warning: Failed to store refresh token or setup watch: $e');
        }
      }

      debugPrint('[AuthService] --- Sign In Complete ---');
      debugPrint('[AuthService] User: ${_appUser?.email} (${_appUser?.uid})');

      return _appUser;
    } catch (e, stackTrace) {
      debugPrint('[AuthService] ERROR during sign in: $e');
      debugPrint('[AuthService] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Migrate flights from anonymous account to Google account
  Future<void> _migrateFlightsFromAnonymous(String anonymousUid, String googleUid) async {
    debugPrint('[AuthService] Migrating flights from $anonymousUid to $googleUid...');

    try {
      // Get all flights from anonymous account
      final anonymousFlights = await _firestore
          .collection('users')
          .doc(anonymousUid)
          .collection('flights')
          .get();

      if (anonymousFlights.docs.isEmpty) {
        debugPrint('[AuthService] No flights to migrate');
        return;
      }

      // Get existing flights from Google account for duplicate detection
      final googleFlights = await _firestore
          .collection('users')
          .doc(googleUid)
          .collection('flights')
          .get();

      final existingKeys = <String>{};
      for (final doc in googleFlights.docs) {
        final data = doc.data();
        final key = _createFlightUniqueKey(data);
        existingKeys.add(key);
      }

      // Migrate non-duplicate flights
      int migratedCount = 0;
      int skippedCount = 0;

      for (final doc in anonymousFlights.docs) {
        final data = doc.data();
        final key = _createFlightUniqueKey(data);

        if (existingKeys.contains(key)) {
          debugPrint('[AuthService] Skipping duplicate flight: $key');
          skippedCount++;
          continue;
        }

        // Add to Google account
        await _firestore
            .collection('users')
            .doc(googleUid)
            .collection('flights')
            .add(data);
        migratedCount++;
      }

      debugPrint('[AuthService] Migration complete: $migratedCount migrated, $skippedCount skipped');
    } catch (e) {
      debugPrint('[AuthService] Error migrating flights: $e');
    }
  }

  /// Create unique key for flight duplicate detection
  String _createFlightUniqueKey(Map<String, dynamic> data) {
    return '${data['flightNumber']}_${data['departureDate']}_${data['departureTime']}_${data['arrivalTime']}_${data['originAirport']}_${data['destinationAirport']}';
  }

  /// Delete anonymous user data after migration
  Future<void> _deleteAnonymousUserData(String anonymousUid) async {
    debugPrint('[AuthService] Deleting anonymous user data: $anonymousUid');

    try {
      // Delete all flights subcollection
      final flights = await _firestore
          .collection('users')
          .doc(anonymousUid)
          .collection('flights')
          .get();

      for (final doc in flights.docs) {
        await doc.reference.delete();
      }

      // Delete user document
      await _firestore.collection('users').doc(anonymousUid).delete();

      debugPrint('[AuthService] Anonymous user data deleted');
    } catch (e) {
      debugPrint('[AuthService] Error deleting anonymous user data: $e');
    }
  }

  /// Create or update user document in Firestore
  Future<AppUser> _createOrUpdateUser(
    User firebaseUser,
    GoogleSignInAccount googleUser,
  ) async {
    final userRef = _firestore.collection('users').doc(firebaseUser.uid);
    final userDoc = await userRef.get();
    final now = DateTime.now();

    if (userDoc.exists) {
      // Update existing user (could be converting from anonymous or updating Google user)
      debugPrint('[AuthService] Updating existing user...');

      final existingData = userDoc.data()!;
      final wasAnonymous = existingData['isAnonymous'] == true;

      if (wasAnonymous) {
        // Converting from anonymous - update with Google info and remove anonymous flag
        debugPrint('[AuthService] Converting anonymous user to Google user...');
        await userRef.update({
          'email': googleUser.email,
          'displayName': googleUser.displayName,
          'photoUrl': googleUser.photoUrl,
          'lastLoginAt': Timestamp.fromDate(now),
          'isAnonymous': FieldValue.delete(),
        });
      } else {
        // Just updating existing Google user
        await userRef.update({
          'lastLoginAt': Timestamp.fromDate(now),
          'displayName': googleUser.displayName,
          'photoUrl': googleUser.photoUrl,
        });
      }

      return AppUser(
        uid: firebaseUser.uid,
        email: googleUser.email,
        displayName: googleUser.displayName,
        photoUrl: googleUser.photoUrl,
        createdAt: (existingData['createdAt'] as Timestamp).toDate(),
        lastLoginAt: now,
      );
    } else {
      // Create new user
      debugPrint('[AuthService] Creating new user...');
      final newUser = AppUser(
        uid: firebaseUser.uid,
        email: googleUser.email,
        displayName: googleUser.displayName,
        photoUrl: googleUser.photoUrl,
        createdAt: now,
        lastLoginAt: now,
      );

      await userRef.set(newUser.toFirestore());
      return newUser;
    }
  }

  /// Load app user from Firestore
  Future<void> _loadAppUser() async {
    if (firebaseUser == null) return;

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(firebaseUser!.uid)
          .get();

      if (userDoc.exists) {
        _appUser = AppUser.fromFirestore(userDoc);
        debugPrint('[AuthService] Loaded app user: ${_appUser?.email}');
      }
    } catch (e) {
      debugPrint('[AuthService] Error loading app user: $e');
    }
  }

  /// Sign out from both Google and Firebase
  Future<void> signOut() async {
    debugPrint('[AuthService] Signing out...');

    try {
      await _googleSignIn.signOut();
      await _firebaseAuth.signOut();
      _googleUser = null;
      _appUser = null;
      debugPrint('[AuthService] Sign out complete');
    } catch (e) {
      debugPrint('[AuthService] Error signing out: $e');
    }
  }

  /// Get Gmail access token (for calling Firebase Functions)
  Future<String?> getGmailAccessToken() async {
    if (_googleUser == null) {
      debugPrint('[AuthService] No Google user, cannot get access token');
      return null;
    }

    try {
      final auth = await _googleUser!.authentication;
      debugPrint('[AuthService] Got Gmail access token (length: ${auth.accessToken?.length})');
      return auth.accessToken;
    } catch (e) {
      debugPrint('[AuthService] Error getting access token: $e');
      return null;
    }
  }

  /// Get Firebase ID token (for authenticated requests)
  Future<String?> getIdToken() async {
    return await firebaseUser?.getIdToken();
  }

  /// Save a flight to Firestore
  Future<void> saveFlight(Map<String, dynamic> flightData) async {
    if (firebaseUser == null) {
      debugPrint('[AuthService] Cannot save flight - no user');
      return;
    }

    try {
      await _firestore
          .collection('users')
          .doc(firebaseUser!.uid)
          .collection('flights')
          .add({
        ...flightData,
        'addedAt': FieldValue.serverTimestamp(),
        'source': 'manual',
      });
      debugPrint('[AuthService] Flight saved to Firestore');
    } catch (e) {
      debugPrint('[AuthService] Error saving flight: $e');
    }
  }

  /// Load all flights from Firestore
  Future<List<Map<String, dynamic>>> loadFlights() async {
    if (firebaseUser == null) {
      debugPrint('[AuthService] Cannot load flights - no user');
      return [];
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(firebaseUser!.uid)
          .collection('flights')
          .orderBy('addedAt', descending: true)
          .get();

      final flights = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      debugPrint('[AuthService] Loaded ${flights.length} flights from Firestore');
      return flights;
    } catch (e) {
      debugPrint('[AuthService] Error loading flights: $e');
      return [];
    }
  }

  /// Delete a flight from Firestore
  Future<void> deleteFlight(String flightId) async {
    if (firebaseUser == null) {
      debugPrint('[AuthService] Cannot delete flight - no user');
      return;
    }

    try {
      await _firestore
          .collection('users')
          .doc(firebaseUser!.uid)
          .collection('flights')
          .doc(flightId)
          .delete();
      debugPrint('[AuthService] Flight deleted from Firestore');
    } catch (e) {
      debugPrint('[AuthService] Error deleting flight: $e');
    }
  }
}
