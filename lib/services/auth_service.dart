import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  late final GoogleSignIn _googleSignIn;

  GoogleSignInAccount? _googleUser;
  AppUser? _appUser;

  AuthService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance {
    _googleSignIn = GoogleSignIn(
      scopes: _scopes,
      clientId: Platform.isIOS ? _iosClientId : null,
      serverClientId: Platform.isAndroid ? _webClientId : null,
    );
  }

  // Current Firebase user
  User? get firebaseUser => _firebaseAuth.currentUser;

  // Current app user (from Firestore)
  AppUser? get currentUser => _appUser;

  // Check if user is signed in
  bool get isSignedIn => firebaseUser != null;

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

    // Try silent sign in if already signed in to Firebase
    if (_firebaseAuth.currentUser != null) {
      debugPrint('[AuthService] Firebase user exists, loading app user...');
      await _loadAppUser();

      // Try silent Google sign in to restore Gmail access
      await _googleSignIn.signInSilently();
      _googleUser = _googleSignIn.currentUser;
    }

    debugPrint('[AuthService] Initialized. Signed in: $isSignedIn');
  }

  /// Sign in with Google and create/update Firebase account
  Future<AppUser?> signInWithGoogle() async {
    debugPrint('[AuthService] --- Sign In Started ---');

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

      // Step 3: Sign in to Firebase with Google credentials
      debugPrint('[AuthService] Signing in to Firebase...');
      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        debugPrint('[AuthService] Firebase sign-in failed - no user returned');
        return null;
      }

      debugPrint('[AuthService] Firebase Sign-In successful: ${firebaseUser.uid}');

      // Step 4: Create or update user in Firestore
      debugPrint('[AuthService] Creating/updating user in Firestore...');
      _appUser = await _createOrUpdateUser(firebaseUser, googleUser);

      debugPrint('[AuthService] --- Sign In Complete ---');
      debugPrint('[AuthService] User: ${_appUser?.email} (${_appUser?.uid})');

      return _appUser;
    } catch (e, stackTrace) {
      debugPrint('[AuthService] ERROR during sign in: $e');
      debugPrint('[AuthService] Stack trace: $stackTrace');
      return null;
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
      // Update existing user
      debugPrint('[AuthService] Updating existing user...');
      await userRef.update({
        'lastLoginAt': Timestamp.fromDate(now),
        'displayName': googleUser.displayName,
        'photoUrl': googleUser.photoUrl,
      });

      return AppUser(
        uid: firebaseUser.uid,
        email: googleUser.email,
        displayName: googleUser.displayName,
        photoUrl: googleUser.photoUrl,
        createdAt: (userDoc.data()!['createdAt'] as Timestamp).toDate(),
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
}
