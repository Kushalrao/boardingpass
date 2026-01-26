import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'services/auth_service.dart';
import 'services/cirium_api_service.dart';
import 'services/notification_service.dart';
import 'models/schedule.dart';
import 'models/flight_status.dart';
import 'models/common.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Google Maps with latest renderer for cloud-based styling
  final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    mapsImplementation.useAndroidViewSurface = true;
    await mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
    debugPrint('[Airtime] Google Maps Android renderer initialized');
  }

  debugPrint('[Airtime] Initializing Firebase...');
  await Firebase.initializeApp();
  debugPrint('[Airtime] Firebase initialized successfully');

  // Register FCM background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  debugPrint('[Airtime] FCM background handler registered');

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
  final CiriumApiService _ciriumService = CiriumApiService();
  GoogleMapController? _mapController;
  bool _isLoading = false;

  // Add flight state
  bool _isAddingFlight = false;
  String _activeField = 'flightNumber'; // 'flightNumber' or 'date'
  String _flightNumber = '';
  DateTime? _selectedDate;
  final TextEditingController _flightNumberController = TextEditingController();
  final FocusNode _flightNumberFocusNode = FocusNode();

  // Search result state
  bool _isSearching = false;
  bool _hasSearched = false;
  List<ScheduledFlight> _searchResults = [];
  Appendix? _appendix;
  String? _searchError;
  int? _selectedResultIndex;

  // Added flights state
  List<({ScheduledFlight flight, Appendix? appendix, String? firestoreId})> _addedFlights = [];
  bool _isLoadingFlights = false;

  // Cape Town / Brackenfell area - default location from Figma
  static const LatLng _defaultLocation = LatLng(-33.8688, 18.7029);

  // Green accent color used throughout
  static const Color _accentGreen = Color(0xFF34C759);
  static const Color _delayedYellow = Color(0xFFD9C700); // Yellow-green for delayed state

  @override
  void initState() {
    super.initState();
    _initAuthService();
    
    _flightNumberController.addListener(() {
      setState(() {
        _flightNumber = _flightNumberController.text;
      });
    });
  }

  Future<void> _initAuthService() async {
    debugPrint('[Airtime] Initializing Auth Service...');
    await _authService.init();
    setState(() {});

    if (_authService.isSignedIn) {
      debugPrint('[Airtime] User already signed in: ${_authService.currentUser?.email}');
    } else if (_authService.isAnonymous) {
      debugPrint('[Airtime] Anonymous user: ${_authService.userId}');
    } else {
      debugPrint('[Airtime] No user signed in');
    }

    // Initialize notifications if user is authenticated
    if (_authService.hasAuth && _authService.userId != null) {
      debugPrint('[Airtime] Initializing notifications...');
      await NotificationService().init(_authService.userId!);
    }

    // Load flights from Firestore
    await _loadFlightsFromFirestore();
  }

  Future<void> _loadFlightsFromFirestore() async {
    if (!_authService.hasAuth) return;

    setState(() => _isLoadingFlights = true);

    try {
      final flightsData = await _authService.loadFlights();
      final loadedFlights = <({ScheduledFlight flight, Appendix? appendix, String? firestoreId})>[];

      for (final data in flightsData) {
        // Reconstruct ScheduledFlight from stored data
        final flight = ScheduledFlight(
          carrierFsCode: data['carrierFsCode'] ?? '',
          flightNumber: data['flightNumber'] ?? '',
          departureAirportFsCode: data['originAirport'] ?? '',
          arrivalAirportFsCode: data['destinationAirport'] ?? '',
          departureTime: data['departureTime'] ?? '',
          arrivalTime: data['arrivalTime'] ?? '',
          stops: data['stops'] ?? 0,
          departureTerminal: data['departureTerminal'],
          arrivalTerminal: data['arrivalTerminal'],
          flightEquipmentIataCode: data['flightEquipmentIataCode'],
          isCodeshare: data['isCodeshare'] ?? false,
          isWetlease: data['isWetlease'] ?? false,
          serviceType: data['serviceType'],
          serviceClasses: List<String>.from(data['serviceClasses'] ?? []),
          trafficRestrictions: List<String>.from(data['trafficRestrictions'] ?? []),
          codeshares: [],
          referenceCode: data['referenceCode'],
        );

        // Reconstruct minimal Appendix for display (airline and airport info)
        Appendix? appendix;
        if (data['airlineName'] != null || data['originCity'] != null || data['destinationCity'] != null) {
          appendix = Appendix(
            airlines: data['airlineName'] != null
                ? [Airline(
                    fs: data['carrierFsCode'] ?? '',
                    name: data['airlineName'],
                    active: true,
                  )]
                : [],
            airports: [
              if (data['originCity'] != null)
                Airport(
                  fs: data['originAirport'] ?? '',
                  name: data['originAirportName'] ?? data['originAirport'] ?? '',
                  city: data['originCity'] ?? '',
                  countryCode: '',
                  countryName: '',
                  regionName: '',
                  timeZoneRegionName: '',
                  utcOffsetHours: 0,
                  latitude: 0,
                  longitude: 0,
                  active: true,
                ),
              if (data['destinationCity'] != null)
                Airport(
                  fs: data['destinationAirport'] ?? '',
                  name: data['destinationAirportName'] ?? data['destinationAirport'] ?? '',
                  city: data['destinationCity'] ?? '',
                  countryCode: '',
                  countryName: '',
                  regionName: '',
                  timeZoneRegionName: '',
                  utcOffsetHours: 0,
                  latitude: 0,
                  longitude: 0,
                  active: true,
                ),
            ],
            equipments: [],
          );
        }

        loadedFlights.add((flight: flight, appendix: appendix, firestoreId: data['id'] as String?));
      }

      setState(() {
        _addedFlights = loadedFlights;
        _isLoadingFlights = false;
      });

      debugPrint('[Airtime] Loaded ${loadedFlights.length} flights');
    } catch (e) {
      debugPrint('[Airtime] Error loading flights: $e');
      setState(() => _isLoadingFlights = false);
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

        // Initialize notifications for the signed-in user
        debugPrint('[Airtime] Initializing notifications...');
        await NotificationService().init(user.uid);

        // Reload flights (may have been migrated from anonymous account)
        await _loadFlightsFromFirestore();

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

  void _handleAddFlightTap() {
    setState(() {
      _isAddingFlight = true;
      _activeField = 'flightNumber';
      // Reset search results when starting new flight add
      _hasSearched = false;
      _searchResults = [];
      _appendix = null;
      _searchError = null;
      _selectedResultIndex = null;
    });
    // Focus the flight number input
    Future.delayed(const Duration(milliseconds: 100), () {
      _flightNumberFocusNode.requestFocus();
    });
  }

  void _handleDateFieldTap() {
    // Dismiss keyboard and show calendar
    _flightNumberFocusNode.unfocus();
    setState(() {
      _activeField = 'date';
    });
  }

  void _handleFlightNumberFieldTap() {
    setState(() {
      _activeField = 'flightNumber';
      // Reset search when going back to edit flight number
      _hasSearched = false;
      _searchResults = [];
      _appendix = null;
      _searchError = null;
      _selectedResultIndex = null;
    });
    _flightNumberFocusNode.requestFocus();
  }

  Future<void> _handleDateSelected(DateTime date) async {
    setState(() {
      _selectedDate = date;
    });

    // Trigger flight search
    await _searchFlight();
  }

  Future<void> _searchFlight() async {
    if (_flightNumber.isEmpty || _selectedDate == null) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      debugPrint('[Airtime] Searching flight: $_flightNumber on ${_selectedDate!.toIso8601String()}');
      
      // Use the Schedules API to search for the flight (works for future dates)
      final response = await _ciriumService.getScheduleByFlightNumber(
        flight: _flightNumber,
        year: _selectedDate!.year,
        month: _selectedDate!.month,
        day: _selectedDate!.day,
      );

      if (response.hasError) {
        setState(() {
          _searchError = response.error?.errorMessage ?? 'Unknown error occurred';
          _searchResults = [];
          _appendix = null;
        });
        debugPrint('[Airtime] Search error: $_searchError');
      } else if (response.scheduledFlights.isEmpty) {
        setState(() {
          _searchError = 'No flights found';
          _searchResults = [];
          _appendix = null;
        });
        debugPrint('[Airtime] No flights found');
        } else {
        setState(() {
          _searchResults = response.scheduledFlights;
          _appendix = response.appendix;
          // If only one result, auto-select it
          if (_searchResults.length == 1) {
            _selectedResultIndex = 0;
          }
        });
        debugPrint('[Airtime] Found ${_searchResults.length} flight(s)');
        // Move map to destination airport
        _moveMapToDestination(_searchResults[0].arrivalAirportFsCode);
      }
    } catch (e) {
      setState(() {
        _searchError = 'Error: ${e.toString()}';
        _searchResults = [];
        _appendix = null;
      });
      debugPrint('[Airtime] Search exception: $e');
    } finally {
      setState(() {
        _isSearching = false;
        _hasSearched = true;
      });
    }
  }

  Future<void> _handleAcceptFlight() async {
    if (_selectedResultIndex == null || _searchResults.isEmpty) return;

    final selectedFlight = _searchResults[_selectedResultIndex!];
    final appendix = _appendix;
    debugPrint('[Airtime] User accepted flight: ${selectedFlight.fullFlightNumber}');

    // Get airline and airport info for storage
    final airlineName = appendix?.getAirline(selectedFlight.carrierFsCode)?.name;
    final originAirport = appendix?.getAirport(selectedFlight.departureAirportFsCode);
    final destinationAirport = appendix?.getAirport(selectedFlight.arrivalAirportFsCode);

    // Save to Firestore
    final flightData = {
      'carrierFsCode': selectedFlight.carrierFsCode,
      'flightNumber': selectedFlight.flightNumber,
      'fullFlightNumber': selectedFlight.fullFlightNumber,
      'originAirport': selectedFlight.departureAirportFsCode,
      'destinationAirport': selectedFlight.arrivalAirportFsCode,
      'departureTime': selectedFlight.departureTime,
      'arrivalTime': selectedFlight.arrivalTime,
      'departureDate': selectedFlight.departureDateTime?.toIso8601String().split('T')[0],
      'stops': selectedFlight.stops,
      'departureTerminal': selectedFlight.departureTerminal,
      'arrivalTerminal': selectedFlight.arrivalTerminal,
      'flightEquipmentIataCode': selectedFlight.flightEquipmentIataCode,
      'isCodeshare': selectedFlight.isCodeshare,
      'isWetlease': selectedFlight.isWetlease,
      'serviceType': selectedFlight.serviceType,
      'serviceClasses': selectedFlight.serviceClasses,
      'trafficRestrictions': selectedFlight.trafficRestrictions,
      'referenceCode': selectedFlight.referenceCode,
      // Store display info
      'airlineName': airlineName,
      'originCity': originAirport?.city,
      'originAirportName': originAirport?.name,
      'destinationCity': destinationAirport?.city,
      'destinationAirportName': destinationAirport?.name,
    };

    await _authService.saveFlight(flightData);

    // Add the flight to local list for immediate display
    setState(() {
      _addedFlights.add((flight: selectedFlight, appendix: appendix, firestoreId: null));
      _isAddingFlight = false;
      _hasSearched = false;
      _searchResults = [];
      _appendix = null;
      _searchError = null;
      _selectedResultIndex = null;
      _flightNumber = '';
      _selectedDate = null;
      _flightNumberController.clear();
    });
  }

  void _handleRejectFlight() {
    debugPrint('[Airtime] User rejected flight');
    
    // Reset and allow user to try again
    setState(() {
      _isAddingFlight = false;
      _hasSearched = false;
      _searchResults = [];
      _appendix = null;
      _searchError = null;
      _selectedResultIndex = null;
      _flightNumber = '';
      _selectedDate = null;
      _flightNumberController.clear();
    });
  }

  void _handleSelectResult(int index) {
    setState(() {
      _selectedResultIndex = index;
    });
    // Move map to selected flight's destination
    _moveMapToDestination(_searchResults[index].arrivalAirportFsCode);
  }

  void _moveMapToDestination(String airportCode) {
    if (_appendix == null || _mapController == null) return;
    
    final airport = _appendix!.getAirport(airportCode);
    if (airport == null) return;
    
    _mapController!.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(airport.latitude, airport.longitude),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '--:--';
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _getAirlineName(String carrierCode) {
    if (_appendix == null) return carrierCode;
    final airline = _appendix!.getAirline(carrierCode);
    return airline?.name ?? carrierCode;
  }

  String _getAirportCity(String airportCode) {
    if (_appendix == null) return airportCode;
    final airport = _appendix!.getAirport(airportCode);
    return airport?.city ?? airportCode;
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _flightNumberController.dispose();
    _flightNumberFocusNode.dispose();
    _ciriumService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Figma design dimensions
    const double figmaWidth = 390.0;
    const double figmaHeight = 844.0;

    // Scale factor for vertical positioning
    final double scaleY = screenHeight / figmaHeight;

    // Fixed card width (372px in Figma, proportional to screen)
    final double cardWidth = (372.0 / figmaWidth) * screenWidth;

    // Positions scaled proportionally
    final double mapHeight = 491.0 * scaleY;
    final double signInCardTop = 320.0 * scaleY;
    
    // Input card position changes based on search state
    double addFlightCardTop;
    if (_hasSearched && _searchResults.isNotEmpty) {
      addFlightCardTop = 527.0 * scaleY; // After search: 527px from Figma
    } else if (_isAddingFlight) {
      addFlightCardTop = 441.0 * scaleY; // During input: 441px
    } else {
      addFlightCardTop = 418.0 * scaleY; // Zero state: 418px
    }
    
    final double calendarTop = 535.0 * scaleY;
    final double flightDetailsTop = 629.0 * scaleY;
    final double actionContainerTop = 727.0 * scaleY;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside
          if (_isAddingFlight && _activeField == 'flightNumber') {
            _flightNumberFocusNode.unfocus();
          }
        },
        child: Container(
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
                  cloudMapId: '62f0e28a3bd3ee4c493ea929',
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),

              // Added flights container (white area at bottom) - hidden when adding flight
              if (!_isAddingFlight)
                Positioned(
                  top: mapHeight,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.white,
                    child: _addedFlights.isEmpty
                      ? Center(
                          child: Text(
                            'No flights added yet',
                            style: GoogleFonts.balooBhai2(
                              fontSize: 27,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withValues(alpha: 0.4),
                              height: 33 / 27,
                            ),
                          ),
                        )
                      : _buildAddedFlightsList(),
                  ),
                ),

              // Calendar component (shown when date field is active and no search yet)
              if (_isAddingFlight && _activeField == 'date' && !_hasSearched)
                Positioned(
                  top: calendarTop,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildCalendarComponent(),
                ),

              // Sign in with Google card (hidden when adding flight)
              if (!_isAddingFlight)
                Positioned(
                  top: signInCardTop,
                  left: (screenWidth - cardWidth) / 2,
                  child: _buildGoogleSignInCard(cardWidth),
                ),

              // Add flight card / input
              Positioned(
                top: addFlightCardTop,
                left: (screenWidth - cardWidth) / 2,
                child: _isAddingFlight
                    ? _buildAddFlightInputCard(cardWidth)
                    : _buildAddFlightCard(cardWidth),
              ),

              // Flight details results (shown after search)
              if (_hasSearched && _searchResults.isNotEmpty)
                Positioned(
                  top: flightDetailsTop,
                  left: 0,
                  right: 0,
                  child: _searchResults.length == 1
                      ? _buildFlightDetailsContainer(_searchResults[0])
                      : _buildMultipleResultsList(),
                ),

              // Action container (shown only for single result)
              if (_hasSearched && _searchResults.length == 1)
                Positioned(
                  top: actionContainerTop,
                  left: 0,
                  right: 0,
                  child: _buildActionContainer(),
                ),

              // Loading indicator during search
              if (_isSearching)
                Positioned(
                  top: flightDetailsTop,
                  left: 0,
                  right: 0,
                  height: 98,
                  child: Container(
                    color: Colors.white,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: _accentGreen,
                      ),
                    ),
                  ),
            ),
        ],
      ),
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
              Color(0xFF34A853), // Google Green
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                height: 35,
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _handleAddFlightTap();
      },
      child: Container(
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  color: _accentGreen,
                  width: 3,
                ),
              ),
              child: SizedBox(
                height: 35,
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
      ),
    );
  }

  Widget _buildAddFlightInputCard(double cardWidth) {
    // After search, both fields have gray border; during input, active field has green
    final bool showGrayBorders = _hasSearched && _searchResults.isNotEmpty;
    
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(27),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 64,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Flight number field
          Expanded(
            child: _buildInputField(
              isActive: !showGrayBorders && _activeField == 'flightNumber',
              isFilled: _flightNumber.isNotEmpty,
              placeholder: 'Flight no.',
              value: _flightNumber.toUpperCase(),
              onTap: _handleFlightNumberFieldTap,
              isTextField: true,
              forceGrayBorder: showGrayBorders,
            ),
          ),
          const SizedBox(width: 19),
          // Date field
          Expanded(
            child: _buildInputField(
              isActive: !showGrayBorders && _activeField == 'date',
              isFilled: _selectedDate != null,
              placeholder: 'Date',
              value: _selectedDate != null ? _formatDate(_selectedDate!) : 'Date',
              onTap: _handleDateFieldTap,
              isTextField: false,
              forceGrayBorder: showGrayBorders,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required bool isActive,
    required bool isFilled,
    required String placeholder,
    required String value,
    required VoidCallback onTap,
    required bool isTextField,
    bool forceGrayBorder = false,
  }) {
    // Determine background and border color based on state
    // After search (forceGrayBorder): white bg, gray border (#CECECE)
    // Active or filled: white bg, green border, black text
    // Inactive and unfilled: green bg, green border, white text
    final bool showWhiteBg = forceGrayBorder || isActive || isFilled;
    final Color bgColor = showWhiteBg ? Colors.white : _accentGreen;
    final Color textColor = showWhiteBg ? Colors.black : Colors.white;
    final Color borderColor = forceGrayBorder ? const Color(0xFFCECECE) : _accentGreen;
    final String displayText = isFilled ? value : placeholder;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: borderColor,
            width: 3,
          ),
        ),
        child: isTextField && isActive
            ? SizedBox(
                height: 35,
                child: Center(
                  child: TextField(
                    controller: _flightNumberController,
                    focusNode: _flightNumberFocusNode,
                    textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                    style: GoogleFonts.balooBhai2(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      height: 35 / 27,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: placeholder,
                      hintStyle: GoogleFonts.balooBhai2(
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        height: 35 / 27,
                      ),
                    ),
                  ),
                ),
              )
            : SizedBox(
                height: 35,
                child: Center(
                  child: Text(
                    displayText,
                    style: GoogleFonts.balooBhai2(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      height: 35 / 27,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildFlightDetailsContainer(ScheduledFlight flight) {
    // Get departure time from schedule
    final departureTime = flight.departureDateTime;
    
    final airlineName = _getAirlineName(flight.carrierFsCode);
    final destinationCity = _getAirportCity(flight.arrivalAirportFsCode);
    
    // Figma specs:
    // Flight details container: w-390, h-98, bg-white
    // Airline: left calc(50%-178px) = 17px, top calc(50%-30px) = 19px, font 17px Medium
    // Destination: left calc(50%-178px) = 17px, top calc(50%-3px) = 46px, font 27px Bold
    // Time box: right 19px, bottom 29px, border #34c759 3px, rounded 11px, padding pb-3 pt-7 px-7
    
    return Container(
      width: 390,
      height: 98,
      color: Colors.white,
      child: Stack(
        children: [
          // Airline name - left side: left calc(50%-178px), top calc(50%-30px)
          Positioned(
            left: 17, // 195 - 178 = 17
            top: 19, // 49 - 30 = 19
            child: Text(
              airlineName,
              style: GoogleFonts.balooBhai2(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: Colors.black,
                height: 23 / 17,
              ),
            ),
          ),
          // Destination - left side below airline: left calc(50%-178px), top calc(50%-3px)
          Positioned(
            left: 17, // 195 - 178 = 17
            top: 46, // 49 - 3 = 46
            child: Text(
              'To $destinationCity',
              style: GoogleFonts.balooBhai2(
                fontSize: 27,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                height: 33 / 27,
              ),
            ),
          ),
          // Departure time box - right side: right 19px, bottom 29px
          Positioned(
            right: 19,
            bottom: 29,
            child: Container(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 7, bottom: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _accentGreen,
                  width: 3,
                ),
              ),
              child: Text(
                _formatTime(departureTime),
                style: GoogleFonts.balooBhai2(
                  fontSize: 31,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  height: 35 / 31,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleResultsList() {
    return Column(
      children: _searchResults.asMap().entries.map((entry) {
        final index = entry.key;
        final flight = entry.value;
        final isSelected = _selectedResultIndex == index;
        
        return GestureDetector(
          onTap: () => _handleSelectResult(index),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: isSelected
                  ? Border.all(color: _accentGreen, width: 2)
                  : null,
            ),
            child: _buildFlightDetailsContainer(flight),
          ),
        );
      }).toList(),
    );
  }

  // Check if flight is delayed (for added flights list)
  Future<bool> _isFlightDelayed(ScheduledFlight flight) async {
    try {
      final departureDate = flight.departureDateTime;
      if (departureDate == null) return false;
      
      final response = await _ciriumService.getFlightStatusByFlightNumber(
        flight: flight.fullFlightNumber,
        year: departureDate.year,
        month: departureDate.month,
        day: departureDate.day,
      );
      
      if (response.hasError || response.flightStatuses.isEmpty) return false;
      
      final flightStatus = response.flightStatuses.first;
      return flightStatus.delays?.hasDepartureDelay ?? false;
    } catch (e) {
      return false;
    }
  }

  Widget _buildAddedFlightsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _addedFlights.length,
      itemBuilder: (context, index) {
        final added = _addedFlights[index];
        final flight = added.flight;
        final appendix = added.appendix;
        
        final airlineName = appendix?.getAirline(flight.carrierFsCode)?.name ?? flight.carrierFsCode;
        final destinationCity = appendix?.getAirport(flight.arrivalAirportFsCode)?.city ?? flight.arrivalAirportFsCode;
        final departureTime = flight.departureDateTime;
        
        return FutureBuilder<bool>(
          future: _isFlightDelayed(flight),
          builder: (context, snapshot) {
            final isDelayed = snapshot.data ?? false;
            final borderColor = isDelayed ? _delayedYellow : _accentGreen;
            
            return GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FlightTrackingPage(
                      flight: flight,
                      appendix: appendix,
                    ),
                  ),
                );
              },
              child: Container(
                width: 390,
                height: 98,
                color: Colors.white,
                child: Stack(
                  children: [
                    Positioned(
                      left: 17,
                      top: 19,
                      child: Text(
                        airlineName,
                        style: GoogleFonts.balooBhai2(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                          height: 23 / 17,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 17,
                      top: 46,
                      child: Text(
                        'To $destinationCity',
                        style: GoogleFonts.balooBhai2(
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                          height: 33 / 27,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 19,
                      bottom: 29,
                      child: Container(
                        padding: const EdgeInsets.only(left: 7, right: 7, top: 7, bottom: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: borderColor,
                            width: 3,
                          ),
                        ),
                        child: Text(
                          _formatTime(departureTime),
                          style: GoogleFonts.balooBhai2(
                            fontSize: 31,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                            height: 35 / 31,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionContainer() {
    // Action container from Figma: 
    // bg-black, h-79, w-390, top 727px
    // X icon (SF Symbol 􀅾): left calc(50%-111px) = 84px, text-[31px]
    // Checkmark (SF Symbol 􀆅): left calc(50%+82px) = 277px, text-[27px]
    // Both: top calc(50%-16.5px) = ~23px (centered vertically with 33px line-height)
    
    return Container(
      width: 390,
      height: 79,
      color: Colors.black,
      child: Stack(
        children: [
          // X icon (reject) - left side: left calc(50%-111px) = 84px
          Positioned(
            left: 84, // 195 - 111 = 84
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _handleRejectFlight();
              },
              child: Center(
                child: Icon(
                  CupertinoIcons.xmark,
                  size: 31,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // Checkmark icon (accept) - right side: left calc(50%+82px) = 277px
          Positioned(
            left: 277, // 195 + 82 = 277
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                _handleAcceptFlight();
              },
              child: Center(
                child: Icon(
                  CupertinoIcons.checkmark,
                  size: 27,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarComponent() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.only(left: 17, top: 17),
            child: Text(
              'Select date',
              style: GoogleFonts.balooBhai2(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: Colors.black,
                height: 23 / 17,
              ),
            ),
          ),
              const SizedBox(height: 16),
          // Calendar grid
          Expanded(
            child: _buildCalendarGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final now = DateTime.now();
    final currentMonth = _selectedDate ?? now;
    final firstDayOfMonth = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDayOfMonth = DateTime(currentMonth.year, currentMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final startWeekday = firstDayOfMonth.weekday; // 1 = Monday, 7 = Sunday

    // Day names
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 
                    'July', 'August', 'September', 'October', 'November', 'December'];

    return Column(
      children: [
        // Month/Year header with navigation
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    final newDate = DateTime(currentMonth.year, currentMonth.month - 1, 1);
                    _selectedDate = _selectedDate != null 
                        ? DateTime(newDate.year, newDate.month, _selectedDate!.day.clamp(1, DateTime(newDate.year, newDate.month + 1, 0).day))
                        : newDate;
                  });
                },
                child: const Icon(CupertinoIcons.chevron_left, size: 20, color: Colors.black),
              ),
              Text(
                '${months[currentMonth.month - 1]} ${currentMonth.year}',
                style: GoogleFonts.balooBhai2(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    final newDate = DateTime(currentMonth.year, currentMonth.month + 1, 1);
                    _selectedDate = _selectedDate != null 
                        ? DateTime(newDate.year, newDate.month, _selectedDate!.day.clamp(1, DateTime(newDate.year, newDate.month + 1, 0).day))
                        : newDate;
                  });
                },
                child: const Icon(CupertinoIcons.chevron_right, size: 20, color: Colors.black),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Day names row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: dayNames.map((day) => SizedBox(
              width: 40,
              child: Center(
                child: Text(
                  day,
                  style: GoogleFonts.balooBhai2(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Calendar days grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.2,
              ),
              itemCount: 42, // 6 weeks * 7 days
              itemBuilder: (context, index) {
                // Calculate day number
                final dayOffset = index - (startWeekday - 1);
                if (dayOffset < 0 || dayOffset >= daysInMonth) {
                  return const SizedBox();
                }
                final day = dayOffset + 1;
                final date = DateTime(currentMonth.year, currentMonth.month, day);
                final isSelected = _selectedDate != null &&
                    _selectedDate!.year == date.year &&
                    _selectedDate!.month == date.month &&
                    _selectedDate!.day == date.day;
                final isToday = now.year == date.year && 
                    now.month == date.month && 
                    now.day == date.day;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _handleDateSelected(date);
                  },
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? _accentGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isToday && !isSelected
                          ? Border.all(color: _accentGreen, width: 1)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: GoogleFonts.balooBhai2(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                );
              },
          ),
        ),
      ),
      ],
    );
  }
}

// ============================================================
// FLIGHT TRACKING PAGE
// ============================================================

class FlightTrackingPage extends StatefulWidget {
  final ScheduledFlight flight;
  final Appendix? appendix;

  const FlightTrackingPage({
    super.key,
    required this.flight,
    this.appendix,
  });

  @override
  State<FlightTrackingPage> createState() => _FlightTrackingPageState();
}

class _FlightTrackingPageState extends State<FlightTrackingPage> {
  final CiriumApiService _ciriumService = CiriumApiService();
  GoogleMapController? _mapController;
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = false;  // Start with false to show page instantly with existing data
  FlightStatus? _flightStatus;
  Appendix? _statusAppendix;
  double _scrollOffset = 0;

  // Colors from Figma - exact values
  static const Color _accentGreen = Color(0xFF34C759);
  static const Color _backgroundLight = Color(0xFFF1F5EB);
  static const Color _cardWhite = Color(0xFFFDFFFA);
  static const Color _flightBadgeBlue = Color(0xFF15357E);
  static const Color _flightBadgeTextBlue = Color(0xFFDCFBFF);
  static const Color _terminalRed = Color(0xFFFF383C);
  static const Color _gateOrange = Color(0xFFF14D00); // Primary/Scapia/400
  static const Color _beltNavy = Color(0xFF202269);
  static const Color _arrivalTimeBg = Color(0xFFE7EBD9);
  static const Color _aircraftBg = Color(0xFFFDFFFA); // Same as cardWhite
  static const Color _delayedYellow = Color(0xFFD9C700); // Yellow-green for delayed state

  @override
  void initState() {
    super.initState();
    _fetchFlightStatus();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  Future<void> _fetchFlightStatus() async {
    // Don't set loading state - page shows instantly with existing data
    // API updates will refresh components in place

    try {
      final departureDate = widget.flight.departureDateTime;
      if (departureDate == null) {
        setState(() {
          _isLoading = false;
        });
        debugPrint('[Airtime] Invalid departure date');
        return;
      }

      debugPrint('[Airtime] Fetching flight status for ${widget.flight.fullFlightNumber}');
      
      final response = await _ciriumService.getFlightStatusByFlightNumber(
        flight: widget.flight.fullFlightNumber,
        year: departureDate.year,
        month: departureDate.month,
        day: departureDate.day,
      );

      if (!mounted) return;
      
      if (response.hasError) {
        debugPrint('[Airtime] Flight status error: ${response.error?.errorMessage}');
        // Fall back to schedule data if status not available
        setState(() {
          _flightStatus = null;
          _statusAppendix = widget.appendix;
          _isLoading = false;
        });
      } else if (response.flightStatuses.isEmpty) {
        debugPrint('[Airtime] No flight status found, using schedule data');
        setState(() {
          _flightStatus = null;
          _statusAppendix = widget.appendix;
          _isLoading = false;
        });
      } else {
        debugPrint('[Airtime] Flight status found');
        final status = response.flightStatuses.first;
        debugPrint('[Airtime] Flight status details:');
        debugPrint('  - operationalTimes: ${status.operationalTimes}');
        debugPrint('  - scheduledGateDeparture: ${status.operationalTimes?.scheduledGateDeparture?.localDateTime}');
        debugPrint('  - publishedDeparture: ${status.operationalTimes?.publishedDeparture?.localDateTime}');
        debugPrint('  - departureDate: ${status.departureDate?.localDateTime}');
        debugPrint('  - Schedule departureDateTime: ${widget.flight.departureDateTime}');
        
        setState(() {
          _flightStatus = status;
          _statusAppendix = response.appendix ?? widget.appendix;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[Airtime] Error fetching flight status: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getDestinationCity() {
    final appendix = _statusAppendix ?? widget.appendix;
    return appendix?.getAirport(widget.flight.arrivalAirportFsCode)?.city ?? widget.flight.arrivalAirportFsCode;
  }

  String _getDepartureAirportName() {
    final appendix = _statusAppendix ?? widget.appendix;
    return appendix?.getAirport(widget.flight.departureAirportFsCode)?.name ?? widget.flight.departureAirportFsCode;
  }

  String _getArrivalAirportName() {
    final appendix = _statusAppendix ?? widget.appendix;
    return appendix?.getAirport(widget.flight.arrivalAirportFsCode)?.name ?? widget.flight.arrivalAirportFsCode;
  }

  LatLng _getDestinationLatLng() {
    final appendix = _statusAppendix ?? widget.appendix;
    final airport = appendix?.getAirport(widget.flight.arrivalAirportFsCode);
    if (airport != null) {
      return LatLng(airport.latitude, airport.longitude);
    }
    return const LatLng(-33.8688, 18.7029); // Default
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '--:--';
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${dateTime.day} ${months[dateTime.month - 1]}';
  }

  // Get departure time - prefer real-time status, fallback to schedule
  DateTime? get _departureTime {
    if (_flightStatus != null) {
      // Try to get time from flight status operational times
      final scheduledGate = _flightStatus!.operationalTimes?.scheduledGateDeparture?.localDateTime;
      final published = _flightStatus!.operationalTimes?.publishedDeparture?.localDateTime;

      // If we have operational times with actual time, use them
      if (scheduledGate != null) return scheduledGate;
      if (published != null) return published;

      // Don't use departureDate as it typically only contains the date, not time
      // Fall through to use schedule data instead
    }

    // Use schedule departure time (always has the actual time)
    return widget.flight.departureDateTime;
  }

  // Get arrival time - prefer real-time status, fallback to schedule
  DateTime? get _arrivalTime {
    if (_flightStatus != null) {
      return _flightStatus!.operationalTimes?.scheduledGateArrival?.localDateTime ??
             _flightStatus!.operationalTimes?.publishedArrival?.localDateTime ??
             _flightStatus!.arrivalDate?.localDateTime;
    }
    return widget.flight.arrivalDateTime;
  }

  // Get terminal info from flight status
  String? get _departureTerminal {
    return _flightStatus?.airportResources?.departureTerminal ?? widget.flight.departureTerminal;
  }

  String? get _arrivalTerminal {
    return _flightStatus?.airportResources?.arrivalTerminal ?? widget.flight.arrivalTerminal;
  }

  String? get _departureGate {
    return _flightStatus?.airportResources?.departureGate;
  }

  String? get _arrivalGate {
    return _flightStatus?.airportResources?.arrivalGate;
  }

  String? get _arrivalBaggage {
    return _flightStatus?.airportResources?.baggage;
  }

  bool get _isOnTime {
    if (_flightStatus == null) return true;
    return !(_flightStatus!.delays?.hasDepartureDelay ?? false);
  }

  // Get equipment info
  String? get _aircraftName {
    if (_flightStatus?.flightEquipment?.scheduledEquipmentIataCode != null) {
      final appendix = _statusAppendix ?? widget.appendix;
      final equipment = appendix?.getEquipment(_flightStatus!.flightEquipment!.scheduledEquipmentIataCode!);
      return equipment?.name;
    }
    if (widget.flight.flightEquipmentIataCode != null) {
      final appendix = _statusAppendix ?? widget.appendix;
      final equipment = appendix?.getEquipment(widget.flight.flightEquipmentIataCode!);
      return equipment?.name;
    }
    return null;
  }

  String? get _aircraftCode {
    return _flightStatus?.flightEquipment?.scheduledEquipmentIataCode ?? 
           widget.flight.flightEquipmentIataCode;
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _ciriumService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    
    // Calculate floating elements position based on scroll
    // Initial positions from Figma
    const double initialBadgeTop = 244.0;
    const double initialCardTop = 281.0;
    const double mapHeight = 386.0;
    
    // When scrolled, badge and card should move up but stay visible
    // In scrolled state: badge is at top (after status bar), card follows
    final double scrolledBadgeTop = statusBarHeight + 16;
    final double scrolledCardTop = statusBarHeight + 80; // Below badge
    
    // Calculate current position based on scroll
    final double badgeTop = initialBadgeTop - (_scrollOffset * 0.8).clamp(0, initialBadgeTop - scrolledBadgeTop);
    final double cardTop = initialCardTop - (_scrollOffset * 0.8).clamp(0, initialCardTop - scrolledCardTop);
    
    // Back button visibility: show standalone when not scrolled, hide when scrolled (integrated into badge)
    final bool showStandaloneBackButton = _scrollOffset < 100;
    final bool showIntegratedBackButton = _scrollOffset >= 100;
    
    return Scaffold(
      body: Container(
        color: _backgroundLight,
        child: Stack(
                children: [
                  // LAYER 1: Scrollable content
                  SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                    children: [
                      // Map at top
              SizedBox(
                          height: mapHeight,
                        width: screenWidth,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _getDestinationLatLng(),
                            zoom: 10.0,
                          ),
                          onMapCreated: (controller) {
                            _mapController = controller;
                          },
                          cloudMapId: '62f0e28a3bd3ee4c493ea929',
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                          compassEnabled: false,
                          mapToolbarEnabled: false,
                        ),
                      ),
                      
                        // Departure info section (starts right after map)
                        _buildDepartureSection(screenWidth),
                        
                        // 17px spacing between containers
                        const SizedBox(height: 17),
                        
                        // Arrival info section
                        _buildArrivalSection(screenWidth),
                        
                        // 17px spacing between containers
                        if (_aircraftName != null || _aircraftCode != null)
                          const SizedBox(height: 17),
                        
                        // Aircraft info section
                        if (_aircraftName != null || _aircraftCode != null)
                          _buildAircraftSection(screenWidth),
                        
                        // Bottom padding + home indicator space
                        SizedBox(height: 34 + MediaQuery.of(context).padding.bottom),
                      ],
                    ),
                  ),
                  
                  // LAYER 2: Floating journey info card (behind flight badge)
                  Positioned(
                    left: 7,
                    top: cardTop,
                    child: Container(
                      width: 376,
                      height: 138,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(23),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.17),
                            blurRadius: 84,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Destination
                          Positioned(
                            left: 17,
                            top: 38,
                            child: Text(
                              'To  ${_getDestinationCity()}',
                              style: GoogleFonts.balooBhai2(
                                fontSize: 29,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                                height: 45 / 29,
                              ),
                            ),
                          ),
                          // Date
                          Positioned(
                            left: 17,
                            bottom: 23,
                            child: Text(
                              _formatDate(_departureTime),
                              style: GoogleFonts.balooBhai2(
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // LAYER 3: Floating flight badge (always on top - highest z-index)
                  Positioned(
                    left: showIntegratedBackButton ? 24 : 24,
                    top: badgeTop,
                    child: GestureDetector(
                      onTap: showIntegratedBackButton ? () => Navigator.pop(context) : null,
                      child: Container(
                        padding: EdgeInsets.only(
                          left: showIntegratedBackButton ? 13 : 13,
                          right: 13,
                          top: 7,
                          bottom: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _flightBadgeBlue,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Integrated back button when scrolled
                            if (showIntegratedBackButton) ...[
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    CupertinoIcons.chevron_left,
                                    size: 20,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              widget.flight.fullFlightNumber,
                              style: GoogleFonts.balooBhai2(
                                fontSize: 37,
                                fontWeight: FontWeight.w800,
                                color: _flightBadgeTextBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                      
                  // LAYER 4: Standalone back button (only when not scrolled)
                  if (showStandaloneBackButton)
                      Positioned(
                      left: 16,
                      top: 60,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              CupertinoIcons.chevron_left,
                              size: 23,
                              color: Colors.black,
                            ),
                        ),
                        ),
                  ),
          ),
                ],
        ),
      ),
    );
  }

  Widget _buildDepartureSection(double screenWidth) {
    // Figma: height 192px
    return Container(
      width: screenWidth,
      height: 192,
      color: _cardWhite,
      child: Stack(
        children: [
          // "Departure" title - Figma: left calc(50%-178px), bottom 130px (from bottom)
          Positioned(
            left: 17,
            top: 29,
            child: Text(
              'Departure',
              style: GoogleFonts.balooBhai2(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                height: 33 / 25,
              ),
            ),
          ),
          // Airport name - Figma: left calc(50%-178px), bottom 96px (from bottom)
          Positioned(
            left: 17,
            top: 63,
            child: SizedBox(
              width: 217,
              child: Text(
                _getDepartureAirportName(),
                style: GoogleFonts.balooBhai2(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                  height: 23 / 17,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Time box with green/yellow border - Figma: right 13px, top 17px
          // Contains both time and status label ("On Time" or "delayed") together
          Positioned(
            right: 13,
            top: 17,
            child: IntrinsicWidth(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: _isOnTime ? _accentGreen : _delayedYellow,
                    width: 4,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Time text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      child: Text(
                        _formatTime(_departureTime),
                        style: GoogleFonts.balooBhai2(
                          fontSize: 31,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                          letterSpacing: 2.17,
                          height: 43 / 31,
                        ),
                      ),
                    ),
                    // Status badge ("On Time" or "delayed") inside the same container
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _isOnTime ? _accentGreen : _delayedYellow,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(9),
                          bottomRight: Radius.circular(9),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _isOnTime ? 'On Time' : 'delayed',
                          style: GoogleFonts.balooBhai2(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: _cardWhite,
                            height: 23 / 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Terminal badge - Figma: left 17px, top 136px
          if (_departureTerminal != null)
            Positioned(
              left: 17,
              bottom: 23,
              child: Container(
                width: 48,
                height: 33,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: _terminalRed, width: 4),
                ),
                child: Center(
                  child: Text(
                    'T${_departureTerminal!}',
                    style: GoogleFonts.balooBhai2(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 31 / 23,
                    ),
                  ),
                ),
              ),
            ),
          // Gate badge - Figma: left 71px, bg #F14D00 (orange)
          if (_departureGate != null)
            Positioned(
              left: _departureTerminal != null ? 71 : 17,
              bottom: 23,
              child: Container(
                height: 33,
                padding: const EdgeInsets.only(left: 8, right: 12),
                decoration: BoxDecoration(
                  color: _gateOrange,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.arrow_turn_up_right,
                      size: 19,
                      color: Color(0xFFFFDDDC),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Gate $_departureGate',
                      style: GoogleFonts.balooBhai2(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFFDDDC),
                        height: 31 / 23,
                      ),
                    ),
                  ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrivalSection(double screenWidth) {
    // Figma: height 176px
    // Calculate gate badge position based on terminal presence
    double gateBadgeLeft = 17;
    if (_arrivalTerminal != null) gateBadgeLeft = 71;
    
    return Container(
      width: screenWidth,
      height: 176,
      color: _cardWhite,
      child: Stack(
        children: [
          // "Arrival" title - Figma: left calc(50%-178px), bottom 153px
          Positioned(
            left: 17,
            top: 13,
            child: Text(
              'Arrival',
              style: GoogleFonts.balooBhai2(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                height: 33 / 25,
              ),
            ),
          ),
          // Airport name - Figma: left calc(50%-178px), bottom 119px, width 217px
          Positioned(
            left: 17,
            top: 47,
            child: SizedBox(
              width: 217,
              child: Text(
                _getArrivalAirportName(),
                style: GoogleFonts.balooBhai2(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                  height: 23 / 17,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Time box (gray background) - Figma: right 13px, bottom 107px
          Positioned(
            right: 13,
            top: 17,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _arrivalTimeBg,
                borderRadius: BorderRadius.circular(13),
              ),
                child: Text(
                  _formatTime(_arrivalTime),
                  style: GoogleFonts.balooBhai2(
                    fontSize: 31,
                  fontWeight: FontWeight.w700,
                    color: Colors.black,
                    letterSpacing: 2.17,
                  height: 43 / 31,
                  ),
                ),
              ),
            ),
          // Terminal badge - Figma: left 17px, top 120px
          if (_arrivalTerminal != null)
            Positioned(
              left: 17,
              bottom: 23,
              child: Container(
                width: 48,
                height: 33,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: _terminalRed, width: 4),
                ),
                child: Center(
                  child: Text(
                    'T${_arrivalTerminal!}',
                    style: GoogleFonts.balooBhai2(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 31 / 23,
                    ),
                  ),
                ),
              ),
            ),
          // Gate badge - Figma: left 71px, bg #F14D00 (orange)
          if (_arrivalGate != null)
            Positioned(
              left: gateBadgeLeft,
              bottom: 23,
              child: Container(
                height: 33,
                padding: const EdgeInsets.only(left: 8, right: 12),
                decoration: BoxDecoration(
                  color: _gateOrange,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.arrow_turn_up_right,
                      size: 19,
                      color: Color(0xFFFFDDDC),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Gate $_arrivalGate',
                      style: GoogleFonts.balooBhai2(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFFDDDC),
                        height: 31 / 23,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Belt badge - Figma: left 203px, bg #202269 (navy)
          if (_arrivalBaggage != null)
            Positioned(
              left: 203,
              bottom: 23,
              child: Container(
                height: 33,
                padding: const EdgeInsets.only(left: 8, right: 12),
                decoration: BoxDecoration(
                  color: _beltNavy,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.bag,
                      size: 19,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Belt $_arrivalBaggage',
                      style: GoogleFonts.balooBhai2(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 31 / 23,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAircraftSection(double screenWidth) {
    // Parse aircraft name (e.g., "Boeing 787-9 Dreamliner")
    // Figma shows: "Boeing 787" as title, "Dreamliner" as subtitle
    String displayName = 'Boeing 787';
    String? subtitle = 'Dreamliner';
    
    if (_aircraftName != null) {
      // Try to parse the aircraft name
      final parts = _aircraftName!.split(' ');
      if (parts.length >= 2) {
        // e.g., "Boeing 787-9 Dreamliner" -> "Boeing 787" + "Dreamliner"
        displayName = '${parts[0]} ${parts[1]}';
        if (parts.length > 2) {
          subtitle = parts.sublist(2).join(' ');
    }
      } else {
        displayName = _aircraftName!;
        subtitle = null;
      }
    }
    
    // Figma: height 93px, bg #FDFFFA (off-white)
    return Container(
      width: screenWidth,
      height: 93,
      color: _aircraftBg, // Now #FDFFFA
      child: Stack(
        children: [
          // Aircraft name - Figma: left 16px, top 17px
          Positioned(
            left: 16,
            top: 17,
            child: Text(
              displayName,
              style: GoogleFonts.balooBhai2(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                height: 33 / 25,
              ),
            ),
          ),
          // Subtitle (e.g., "Dreamliner") - Figma: left calc(50%-179px), top 53px
          if (subtitle != null)
            Positioned(
              left: 16,
              top: 53,
              child: Text(
                subtitle,
                style: GoogleFonts.balooBhai2(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                  height: 23 / 17,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
