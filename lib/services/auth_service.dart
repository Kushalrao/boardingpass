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
      '69101330162-lp859j8rdim3615omh1v0e12fttc9tdm.apps.googleusercontent.com';

  // iOS Client ID
  static const String _iosClientId =
      '69101330162-564j0e9ur8vbhchecl8v5r5p9v7vndoi.apps.googleusercontent.com';

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
      clientId: defaultTargetPlatform == TargetPlatform.iOS ? _iosClientId : null,
      serverClientId: _webClientId,
      forceCodeForRefreshToken: true,
    );
  }

  // Current Firebase user
  User? get firebaseUser => _firebaseAuth.currentUser;

  // Current app user (from Firestore)
  AppUser? get currentUser => _appUser;

  // Check if user is signed in with Google
  bool get isSignedIn => firebaseUser != null;

  // Get user ID
  String? get userId => firebaseUser?.uid;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// Initialize the auth service
  Future<void> init() async {
    debugPrint('[AuthService] Initializing...');

    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      _googleUser = account;
      debugPrint('[AuthService] Google user changed: ${account?.email}');
    });

    if (_firebaseAuth.currentUser != null) {
      debugPrint('[AuthService] User exists, loading app user...');
      await _loadAppUser();
      await _googleSignIn.signInSilently();
      _googleUser = _googleSignIn.currentUser;
    }

    debugPrint('[AuthService] Initialized. Signed in: $isSignedIn');
  }

  /// Sign in with Google
  Future<AppUser?> signInWithGoogle() async {
    debugPrint('[AuthService] --- Sign In Started ---');

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint('[AuthService] Google Sign-In cancelled by user');
        return null;
      }

      _googleUser = googleUser;
      debugPrint('[AuthService] Google Sign-In successful: ${googleUser.email}');

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        debugPrint('[AuthService] Firebase sign-in failed - no user returned');
        return null;
      }

      debugPrint('[AuthService] Firebase Sign-In successful: ${user.uid}');

      // Create or update user in Firestore
      _appUser = await _createOrUpdateUser(user, googleUser);

      // Store refresh token for backend Gmail access
      final serverAuthCode = googleUser.serverAuthCode;
      if (serverAuthCode != null) {
        debugPrint('[AuthService] Storing refresh token...');
        try {
          await _functions.httpsCallable('storeRefreshToken').call({
            'authCode': serverAuthCode,
          });
          debugPrint('[AuthService] Refresh token stored successfully');

          await _functions.httpsCallable('setupGmailWatch').call();
          debugPrint('[AuthService] Gmail watch set up successfully');
        } catch (e) {
          debugPrint('[AuthService] Warning: Failed to store refresh token or setup watch: $e');
        }
      }

      debugPrint('[AuthService] --- Sign In Complete ---');
      return _appUser;
    } catch (e, stackTrace) {
      debugPrint('[AuthService] ERROR during sign in: $e');
      debugPrint('[AuthService] Stack trace: $stackTrace');
      rethrow;
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
      await userRef.update({
        'lastLoginAt': Timestamp.fromDate(now),
        'displayName': googleUser.displayName,
        'photoUrl': googleUser.photoUrl,
      });

      final existingData = userDoc.data()!;
      return AppUser(
        uid: firebaseUser.uid,
        email: googleUser.email,
        displayName: googleUser.displayName,
        photoUrl: googleUser.photoUrl,
        createdAt: (existingData['createdAt'] as Timestamp?)?.toDate() ?? now,
        lastLoginAt: now,
      );
    } else {
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

  /// Get Gmail access token
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

  /// Get Firebase ID token
  Future<String?> getIdToken() async {
    return await firebaseUser?.getIdToken();
  }

  /// Store date of birth for PDF password resolution
  Future<void> storeDateOfBirth(DateTime dob) async {
    if (firebaseUser == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(firebaseUser!.uid)
          .update({'dateOfBirth': Timestamp.fromDate(dob)});
      debugPrint('[AuthService] DOB stored successfully');
    } catch (e) {
      debugPrint('[AuthService] Error storing DOB: $e');
    }
  }

  /// Check if user has stored their date of birth
  Future<bool> hasDateOfBirth() async {
    if (firebaseUser == null) return false;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(firebaseUser!.uid)
          .get();
      return doc.data()?['dateOfBirth'] != null;
    } catch (e) {
      return false;
    }
  }
}
