import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[Airtime] Initializing Firebase...');
  await Firebase.initializeApp();
  debugPrint('[Airtime] Firebase initialized successfully');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Airtime',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _authService = AuthService();
  GoogleMapController? _mapController;
  bool _isLoading = false;

  // Cape Town / Brackenfell area - default location from Figma
  static const LatLng _defaultLocation = LatLng(-33.8688, 18.7029);

  @override
  void initState() {
    super.initState();
    _initAuthService();
  }

  Future<void> _initAuthService() async {
    debugPrint('[Airtime] Initializing Auth Service...');
    await _authService.init();
    setState(() {});

    if (_authService.isSignedIn) {
      debugPrint('[Airtime] User already signed in: ${_authService.currentUser?.email}');
    } else {
      debugPrint('[Airtime] No user signed in');
    }
  }

  Future<void> _handleGoogleSignIn() async {
    debugPrint('[Airtime] --- Google Sign In Started ---');
    setState(() => _isLoading = true);

    try {
      final user = await _authService.signInWithGoogle();

      if (user != null) {
        debugPrint('[Airtime] Sign in successful!');
        debugPrint('[Airtime] User ID: ${user.uid}');
        debugPrint('[Airtime] Email: ${user.email}');
        setState(() {});
      } else {
        debugPrint('[Airtime] Sign in returned null (user cancelled or error)');
      }
    } catch (e, stackTrace) {
      debugPrint('[Airtime] ERROR during sign in: $e');
      debugPrint('[Airtime] Stack trace: $stackTrace');
    } finally {
      setState(() => _isLoading = false);
      debugPrint('[Airtime] --- Google Sign In Ended ---');
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Figma design dimensions
    const double figmaWidth = 390.0;
    const double figmaHeight = 844.0;

    // Scale factor for vertical positioning (keeps proportions on different screen sizes)
    final double scaleY = screenHeight / figmaHeight;

    // Fixed card width (372px in Figma, or proportional to screen)
    // Using proportional to screen width for consistency across devices
    final double cardWidth = (372.0 / figmaWidth) * screenWidth;

    // Positions scaled proportionally
    final double mapHeight = 491.0 * scaleY;
    final double signInCardTop = 320.0 * scaleY;
    final double addFlightCardTop = 418.0 * scaleY;

    return Scaffold(
      body: Container(
        color: const Color(0xFFF0F0E1),
        child: Stack(
          children: [
            // Map container - edge to edge, behind status bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: mapHeight,
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _defaultLocation,
                  zoom: 11.0,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                mapType: MapType.normal,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),

            // Added flights container (white area at bottom)
            Positioned(
              top: mapHeight,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.white,
                child: Center(
                  child: Text(
                    'No flights added yet',
                    style: GoogleFonts.balooBhai2(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.4),
                      height: 33 / 27,
                    ),
                  ),
                ),
              ),
            ),

            // Sign in with Google card
            Positioned(
              top: signInCardTop,
              left: (screenWidth - cardWidth) / 2,
              child: _buildGoogleSignInCard(cardWidth),
            ),

            // Add flight card
            Positioned(
              top: addFlightCardTop,
              left: (screenWidth - cardWidth) / 2,
              child: _buildAddFlightCard(cardWidth),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleSignInCard(double cardWidth) {
    return GestureDetector(
      onTap: _isLoading ? null : _handleGoogleSignIn,
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.only(
          left: 21,
          right: 21,
          top: 17,
          bottom: 15,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFFEA4335), // Google Red
              Color(0xFFFBBC05), // Google Yellow
              Color(0xFF34A853), // Google Green (FIXED: was #34C759)
              Color(0xFF4285F4), // Google Blue
            ],
            stops: [0.0, 0.4158, 0.6608, 1.0],
          ),
          borderRadius: BorderRadius.circular(19),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 64,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start, // FIXED: items-start from Figma
          children: [
            // Left side: Logo + Text
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Google Logo
                Image.asset(
                  'assets/google_logo.png',
                  width: 39,
                  height: 39,
                  fit: BoxFit.cover,
                ),
                const SizedBox(width: 13),
                // Text content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sign in with Google',
                      style: GoogleFonts.balooBhai2(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 23 / 19,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Automatically add your flights',
                      style: GoogleFonts.balooBhai2(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.57),
                        height: 21 / 15,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Right arrow button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
              ),
              child: SizedBox(
                height: 35, // line-height from Figma
                child: const Center(
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 27,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddFlightCard(double cardWidth) {
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.only(
        left: 21,
        right: 21,
        top: 21,
        bottom: 15,
      ),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(19),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 64,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start, // FIXED: items-start from Figma
        children: [
          // Text content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add your flight',
                style: GoogleFonts.balooBhai2(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 23 / 19,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Enter your flight number',
                style: GoogleFonts.balooBhai2(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.57),
                  height: 21 / 15,
                ),
              ),
            ],
          ),
          // Plus button with green border
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: const Color(0xFF34C759), // Apple Green (correct for this button)
                width: 3,
              ),
            ),
            child: SizedBox(
              height: 35, // line-height from Figma
              child: const Center(
                child: Icon(
                  CupertinoIcons.plus,
                  size: 27,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
