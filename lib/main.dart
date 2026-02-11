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
import 'services/flight_tracking_foreground_service.dart';
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

// ============================================================
// TRIP MODEL - Unified model for both flights and trains
// ============================================================

enum TripType { flight, train }

class Trip {
  final TripType type;
  final String id;
  final DateTime departureDateTime;
  final DateTime? arrivalDateTime;
  final String originCity;
  final String destinationCity;
  final String transportName; // e.g., "Air India AI 2447" or "Sainik Express"
  final bool isDelayed;
  final int? delayMinutes;

  // Flight-specific data
  final ScheduledFlight? flight;
  final Appendix? appendix;
  final String? firestoreId;

  Trip({
    required this.type,
    required this.id,
    required this.departureDateTime,
    this.arrivalDateTime,
    required this.originCity,
    required this.destinationCity,
    required this.transportName,
    this.isDelayed = false,
    this.delayMinutes,
    this.flight,
    this.appendix,
    this.firestoreId,
  });

  bool get isUpcoming => departureDateTime.isAfter(DateTime.now());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final CiriumApiService _ciriumService = CiriumApiService();
  final FlightTrackingForegroundService _flightTrackingService =
      FlightTrackingForegroundService();
  GoogleMapController? _mapController;

  // Trips state (combined flights and trains)
  List<Trip> _trips = [];
  bool _isLoadingTrips = false;

  // Search mode state
  bool _isSearchMode = false;
  late AnimationController _searchAnimationController;
  late Animation<double> _searchSlideAnimation;
  late Animation<double> _homeSlideAnimation;
  late Animation<double> _fadeAnimation;

  // Search input state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showDatePicker = false;
  DateTime _selectedDate = DateTime.now();

  // Date picker animation
  late AnimationController _datePickerAnimationController;
  late Animation<double> _datePickerWidthAnimation;

  // Flight tracking mode state
  bool _isFlightTrackingMode = false;
  Trip? _selectedTrip;
  FlightStatus? _trackingFlightStatus;
  Appendix? _trackingAppendix;
  late AnimationController _flightTrackingAnimationController;
  late Animation<double> _flightTrackingFadeAnimation;

  // Cape Town / Brackenfell area - default location from Figma
  static const LatLng _defaultLocation = LatLng(-33.8688, 18.7029);

  // Design colors from Figma
  static const Color _backgroundColor = Color(0xFFF0F0E1);
  static const Color _searchBarBg = Color(0xFFEEF0EB);
  static const Color _previousSectionBg = Color(0xFFF5F7F2);
  static const Color _dateBoxBlue = Color(0xFF006ECF);
  static const Color _statusBarGreen = Color(0xFF00E439);
  static const Color _statusBarYellow = Color(0xFFFFBF00);
  static const Color _onTimeTextGreen = Color(0xFF05B331);
  static const Color _lateTextYellow = Color(0xFFCA9805);

  // Flight tracking colors from Figma
  static const Color _stepHighlightYellow = Color(0xFFFFCC00); // #fc0
  static const Color _onTimeGreen = Color(0xFF34C759);
  static const Color _badgeBgGray = Color(0xFFF5F7F2);
  static const Color _dotGray = Color(0xFFE0E0E0);

  // Figma base dimensions
  static const double _figmaWidth = 390.0;

  // Pattern detection for search input
  static final RegExp _flightPattern = RegExp(r'^[A-Za-z]{2,3}\d+$');
  static final RegExp _trainPattern = RegExp(r'^\d{5}$');

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initAuthService();
    _searchController.addListener(_onSearchChanged);
    _initFlightTracking();
  }

  // ==========================================================
  // STANDARD TRANSITION SETTINGS (use consistently across app)
  // Duration: 280ms
  // Curve: Curves.easeOutQuart
  // Slide: 20% of width (subtle movement)
  // Always combine slide with fade for smooth crossfade
  // ==========================================================

  void _initAnimations() {
    // Main search/home transition animation - subtle and smooth
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );

    // Subtle slide - only 20% of screen width for gentle movement
    _searchSlideAnimation = Tween<double>(
      begin: 0.2,  // Start slightly to the right
      end: 0.0,    // End at center
    ).animate(CurvedAnimation(
      parent: _searchAnimationController,
      curve: Curves.easeOutQuart,
    ));

    _homeSlideAnimation = Tween<double>(
      begin: 0.0,   // Start at center
      end: -0.2,   // End slightly to the left
    ).animate(CurvedAnimation(
      parent: _searchAnimationController,
      curve: Curves.easeOutQuart,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _searchAnimationController,
      curve: Curves.easeOutQuart,
    ));

    // Date picker width animation - short but very smooth
    _datePickerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );

    _datePickerWidthAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _datePickerAnimationController,
      curve: Curves.easeOutQuart,
    ));

    // Flight tracking mode animation - slide transition
    _flightTrackingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );

    _flightTrackingFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _flightTrackingAnimationController,
      curve: Curves.easeOutQuart,
    ));
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    final shouldShowDatePicker = _isFlightOrTrainNumber(query);

    setState(() {
      _searchQuery = query;
    });

    if (shouldShowDatePicker != _showDatePicker) {
      setState(() {
        _showDatePicker = shouldShowDatePicker;
      });
      if (shouldShowDatePicker) {
        _datePickerAnimationController.forward();
      } else {
        _datePickerAnimationController.reverse();
      }
    }
  }

  bool _isFlightOrTrainNumber(String query) {
    if (query.isEmpty) return false;
    return _flightPattern.hasMatch(query) || _trainPattern.hasMatch(query);
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

    // Load trips from Firestore
    await _loadTrips();

    // Start live tracking notifications for eligible flights
    _startFlightTrackingForTrips();
  }

  Future<void> _loadTrips() async {
    if (!_authService.hasAuth) return;

    setState(() => _isLoadingTrips = true);

    try {
      final flightsData = await _authService.loadFlights();
      final loadedTrips = <Trip>[];

      for (final data in flightsData) {
        // Parse departure time
        DateTime? departureDateTime;
        if (data['departureTime'] != null) {
          try {
            departureDateTime = DateTime.parse(data['departureTime']);
          } catch (e) {
            debugPrint('[Airtime] Error parsing departure time: $e');
          }
        }

        if (departureDateTime == null) continue;

        // Reconstruct ScheduledFlight for navigation to detail page
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

        // Reconstruct minimal Appendix for display
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

        // Build transport name (e.g., "Air India AI 2447")
        final airlineName = data['airlineName'] ?? data['carrierFsCode'] ?? '';
        final fullFlightNumber = data['fullFlightNumber'] ?? '${data['carrierFsCode']}${data['flightNumber']}';
        final transportName = '$airlineName $fullFlightNumber';

        loadedTrips.add(Trip(
          type: TripType.flight,
          id: data['id'] ?? '',
          departureDateTime: departureDateTime,
          arrivalDateTime: data['arrivalTime'] != null ? DateTime.tryParse(data['arrivalTime']) : null,
          originCity: data['originCity'] ?? data['originAirport'] ?? '',
          destinationCity: data['destinationCity'] ?? data['destinationAirport'] ?? '',
          transportName: transportName,
          isDelayed: false, // Will be updated by delay check
          flight: flight,
          appendix: appendix,
          firestoreId: data['id'] as String?,
        ));
      }

      // Sort trips by departure date (soonest first)
      loadedTrips.sort((a, b) => a.departureDateTime.compareTo(b.departureDateTime));

      setState(() {
        _trips = loadedTrips;
        _isLoadingTrips = false;
      });

      debugPrint('[Airtime] Loaded ${loadedTrips.length} trips');

      // Check for delays in background
      _checkDelaysForTrips();
    } catch (e) {
      debugPrint('[Airtime] Error loading trips: $e');
      setState(() => _isLoadingTrips = false);
    }
  }

  Future<void> _checkDelaysForTrips() async {
    for (int i = 0; i < _trips.length; i++) {
      final trip = _trips[i];
      if (trip.type == TripType.flight && trip.flight != null) {
        try {
          final response = await _ciriumService.getFlightStatusByFlightNumber(
            flight: trip.flight!.fullFlightNumber,
            year: trip.departureDateTime.year,
            month: trip.departureDateTime.month,
            day: trip.departureDateTime.day,
          );

          if (!response.hasError && response.flightStatuses.isNotEmpty) {
            final flightStatus = response.flightStatuses.first;
            final isDelayed = flightStatus.delays?.hasDepartureDelay ?? false;
            final delayMinutes = flightStatus.delays?.departureGateDelayMinutes ?? 0;

            if (isDelayed && mounted) {
              setState(() {
                _trips[i] = Trip(
                  type: trip.type,
                  id: trip.id,
                  departureDateTime: trip.departureDateTime,
                  arrivalDateTime: trip.arrivalDateTime,
                  originCity: trip.originCity,
                  destinationCity: trip.destinationCity,
                  transportName: trip.transportName,
                  isDelayed: true,
                  delayMinutes: delayMinutes,
                  flight: trip.flight,
                  appendix: trip.appendix,
                  firestoreId: trip.firestoreId,
                );
              });
            }
          }
        } catch (e) {
          debugPrint('[Airtime] Error checking delay for trip ${trip.id}: $e');
        }
      }
    }
  }

  // ============================================================
  // FLIGHT TRACKING FOREGROUND SERVICE (live notifications)
  // ============================================================

  Future<void> _initFlightTracking() async {
    await _flightTrackingService.init();
  }

  void _startFlightTrackingForTrips() {
    final flightData = _trips
        .where((t) => t.type == TripType.flight && t.firestoreId != null)
        .map((t) => FlightTrackingData(
              firestoreId: t.firestoreId!,
              flightNumber: t.flight?.fullFlightNumber ?? '',
              originCity: t.originCity,
              destinationCity: t.destinationCity,
              departureDateTime: t.departureDateTime,
              arrivalDateTime: t.arrivalDateTime,
              departureTerminal: t.flight?.departureTerminal,
              arrivalTerminal: t.flight?.arrivalTerminal,
            ))
        .toList();

    if (flightData.isNotEmpty) {
      _flightTrackingService.evaluateFlights(flightData);
    }
  }

  List<Trip> get _upcomingTrips => _trips.where((t) => t.isUpcoming).toList();
  List<Trip> get _previousTrips => _trips.where((t) => !t.isUpcoming).toList();

  String _formatMonth(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  void _handleSearchTap() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSearchMode = true;
    });
    _searchAnimationController.forward();
    // Focus the search field after animation starts
    Future.delayed(const Duration(milliseconds: 100), () {
      _searchFocusNode.requestFocus();
    });
  }

  void _handleSearchBack() {
    HapticFeedback.mediumImpact();
    _searchFocusNode.unfocus();
    _searchAnimationController.reverse().then((_) {
      setState(() {
        _isSearchMode = false;
        _searchController.clear();
        _searchQuery = '';
        _showDatePicker = false;
      });
      _datePickerAnimationController.reset();
    });
  }

  void _handleDateTap() {
    HapticFeedback.lightImpact();
    _showDatePickerModal();
  }

  void _showDatePickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _DatePickerBottomSheet(
        selectedDate: _selectedDate,
        onDateSelected: (date) {
          setState(() {
            _selectedDate = date;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _handleProfileTap() {
    // TODO: Navigate to profile page
    HapticFeedback.mediumImpact();
    debugPrint('[Airtime] Profile tapped - to be implemented');
  }

  void _handleTripTap(Trip trip) {
    HapticFeedback.mediumImpact();
    if (trip.type == TripType.flight && trip.flight != null) {
      setState(() {
        _isFlightTrackingMode = true;
        _selectedTrip = trip;
        _trackingAppendix = trip.appendix;
      });
      _flightTrackingAnimationController.forward();
      _fetchTrackingFlightStatus(trip);
    }
  }

  void _handleFlightTrackingBack() {
    HapticFeedback.mediumImpact();
    _flightTrackingAnimationController.reverse().then((_) {
      setState(() {
        _isFlightTrackingMode = false;
        _selectedTrip = null;
        _trackingFlightStatus = null;
        _trackingAppendix = null;
      });
    });
  }

  Future<void> _fetchTrackingFlightStatus(Trip trip) async {
    if (trip.flight == null) return;

    try {
      final departureDate = trip.flight!.departureDateTime;
      if (departureDate == null) return;

      final response = await _ciriumService.getFlightStatusByFlightNumber(
        flight: trip.flight!.fullFlightNumber,
        year: departureDate.year,
        month: departureDate.month,
        day: departureDate.day,
      );

      if (!mounted) return;

      if (!response.hasError && response.flightStatuses.isNotEmpty) {
        setState(() {
          _trackingFlightStatus = response.flightStatuses.first;
          _trackingAppendix = response.appendix ?? trip.appendix;
        });
      }
    } catch (e) {
      debugPrint('[Airtime] Error fetching tracking flight status: $e');
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _ciriumService.dispose();
    _searchAnimationController.dispose();
    _datePickerAnimationController.dispose();
    _flightTrackingAnimationController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _flightTrackingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = screenWidth / _figmaWidth;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // Figma dimensions scaled
    final mapHeight = 404.0 * scale;
    final containerTop = 371.0 * scale;

    // When keyboard is visible, adjust container to keep input visible
    // Only adjust based on keyboard, not search mode
    final keyboardAdjustment = keyboardHeight > 0 ? keyboardHeight * 0.4 : 0.0;
    final adjustedContainerTop = (containerTop - keyboardAdjustment).clamp(100.0 * scale, containerTop);

    return Scaffold(
      body: Container(
        color: _backgroundColor,
        child: Stack(
          children: [
            // Map container - full width at top
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

            // White container with content - overlaps map
            // Follows keyboard height directly for synced animation
            Positioned(
              top: _isFlightTrackingMode || _flightTrackingAnimationController.isAnimating
                  ? 153.0 * scale  // Flight tracking: higher up to show more map
                  : adjustedContainerTop,
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: Listenable.merge([_searchAnimationController, _flightTrackingAnimationController]),
                builder: (context, child) {
                  final searchProgress = _fadeAnimation.value;
                  final trackingProgress = _flightTrackingFadeAnimation.value;

                  // Input field animates from home position (23px) to search position (93px)
                  final inputTopHome = 23.0 * scale;
                  final inputTopSearch = 93.0 * scale;
                  final inputTop = inputTopHome + (inputTopSearch - inputTopHome) * searchProgress;

                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      children: [
                        // Layer 1: Home/Trips content (slides left and fades out)
                        Transform.translate(
                          offset: Offset(-screenWidth * 0.2 * trackingProgress, 0),
                          child: Opacity(
                            opacity: (1.0 - searchProgress) * (1.0 - trackingProgress),
                            child: _buildTripsOnlyContent(scale),
                          ),
                        ),

                        // Layer 2: Search header (fades in with slight slide)
                        if (_isSearchMode || _searchAnimationController.isAnimating)
                          Transform.translate(
                            offset: Offset(0, -20 * scale * (1.0 - searchProgress)),
                            child: Opacity(
                              opacity: searchProgress * (1.0 - trackingProgress),
                              child: _buildSearchHeader(scale),
                            ),
                          ),

                        // Layer 3: Input field row (hide when flight tracking)
                        if (!_isFlightTrackingMode && !_flightTrackingAnimationController.isAnimating)
                          Positioned(
                            top: inputTop,
                            left: 19 * scale,
                            right: 19 * scale,
                            child: _buildAnimatedInputRow(scale, searchProgress),
                          ),

                        // Layer 4: Flight tracking content (slides in from right)
                        if (_isFlightTrackingMode || _flightTrackingAnimationController.isAnimating)
                          Transform.translate(
                            offset: Offset(screenWidth * 0.2 * (1.0 - trackingProgress), 0),
                            child: Opacity(
                              opacity: trackingProgress,
                              child: _buildFlightTrackingContent(scale),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Search header with back button and title (fades in during transition)
  Widget _buildSearchHeader(double scale) {
    return Padding(
      padding: EdgeInsets.only(
        left: 17 * scale,
        right: 17 * scale,
        top: 27 * scale,
      ),
      child: SizedBox(
        height: 33 * scale,
        child: Stack(
          children: [
            // Back button
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _handleSearchBack,
                child: Center(
                  child: Icon(
                    CupertinoIcons.chevron_left,
                    size: 27 * scale,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            // "Search" title centered
            Center(
              child: Text(
                'Search',
                style: GoogleFonts.balooBhai2(
                  fontSize: 27 * scale,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                  height: 33 / 27,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Animated input row - input stays, profile fades out
  Widget _buildAnimatedInputRow(double scale, double progress) {
    final isSearching = _isSearchMode || progress > 0;

    return AnimatedBuilder(
      animation: _datePickerAnimationController,
      builder: (context, child) {
        final showDate = _showDatePicker || _datePickerAnimationController.isAnimating;
        final dateWidthFactor = _datePickerWidthAnimation.value;

        return LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;

            // Profile button width shrinks as progress increases
            final profileTotalWidth = (8 * scale + 53 * scale) * (1.0 - progress);
            final availableForInput = totalWidth - profileTotalWidth;

            // Date field calculations
            final gap = 17 * scale;
            final dateWidth = showDate ? ((availableForInput - gap) / 2) * dateWidthFactor : 0.0;
            final searchWidth = showDate
                ? availableForInput - dateWidth - (dateWidthFactor > 0 ? gap : 0)
                : availableForInput;

            return Row(
              children: [
                // Search input field
                SizedBox(
                  width: searchWidth,
                  child: GestureDetector(
                    onTap: isSearching ? null : _handleSearchTap,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 19 * scale,
                        vertical: 17 * scale,
                      ),
                      decoration: const BoxDecoration(
                        color: _searchBarBg,
                      ),
                      child: progress > 0.5
                          ? TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: GoogleFonts.balooBhai2(
                                fontSize: 19 * scale,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                                height: 27 / 19,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search',
                                hintStyle: GoogleFonts.balooBhai2(
                                  fontSize: 19 * scale,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black.withValues(alpha: 0.5),
                                  height: 27 / 19,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              textInputAction: TextInputAction.search,
                              textCapitalization: TextCapitalization.characters,
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Search flight or train',
                                  style: GoogleFonts.balooBhai2(
                                    fontSize: 19 * scale,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                    height: 27 / 19,
                                  ),
                                ),
                                Icon(
                                  CupertinoIcons.search,
                                  size: 22 * scale,
                                  color: Colors.black,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),

                // Gap + Date field
                if (showDate && dateWidthFactor > 0) ...[
                  SizedBox(width: gap),
                  SizedBox(
                    width: dateWidth,
                    child: Opacity(
                      opacity: dateWidthFactor,
                      child: GestureDetector(
                        onTap: _handleDateTap,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 19 * scale,
                            vertical: 17 * scale,
                          ),
                          decoration: const BoxDecoration(
                            color: _searchBarBg,
                          ),
                          child: Text(
                            _formatDateForSearch(_selectedDate),
                            style: GoogleFonts.balooBhai2(
                              fontSize: 19 * scale,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              height: 27 / 19,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // Profile button (fades out)
                if (progress < 1.0) ...[
                  SizedBox(width: 8 * scale * (1.0 - progress)),
                  Opacity(
                    opacity: 1.0 - progress,
                    child: GestureDetector(
                      onTap: _handleProfileTap,
                      child: Container(
                        width: 53 * scale * (1.0 - progress),
                        height: 53 * scale,
                        decoration: BoxDecoration(
                          color: _searchBarBg,
                          borderRadius: BorderRadius.circular(60 * scale),
                        ),
                        child: Center(
                          child: Icon(
                            CupertinoIcons.person_fill,
                            size: 28 * scale,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // Trips content only (without search bar)
  Widget _buildTripsOnlyContent(double scale) {
    // Calculate top padding to account for search bar area
    final searchBarAreaHeight = 23 * scale + 61 * scale; // top padding + input height

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spacer for search bar area
          SizedBox(height: searchBarAreaHeight + 12 * scale),

          // "Next up" section
          if (_upcomingTrips.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(
                left: 19 * scale,
                top: 35 * scale,
                bottom: 11 * scale,
              ),
              child: Text(
                'Next up',
                style: GoogleFonts.balooBhai2(
                  fontSize: 27 * scale,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                  height: 33 / 27,
                ),
              ),
            ),
            // Upcoming trip cards
            ..._upcomingTrips.map((trip) => _buildTripCard(trip, scale, isUpcoming: true)),
          ],

          // "Previous" section
          if (_previousTrips.isNotEmpty) ...[
            Container(
              width: double.infinity,
              color: _previousSectionBg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: 19 * scale,
                      top: 27 * scale,
                      bottom: 11 * scale,
                    ),
                    child: Text(
                      'Previous',
                      style: GoogleFonts.balooBhai2(
                        fontSize: 27 * scale,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                        height: 33 / 27,
                      ),
                    ),
                  ),
                  // Previous trip cards
                  ..._previousTrips.map((trip) => _buildTripCard(trip, scale, isUpcoming: false)),
                  SizedBox(height: 34 * scale), // Bottom padding
                ],
              ),
            ),
          ],

          // Empty state
          if (_trips.isEmpty && !_isLoadingTrips)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 19 * scale,
                vertical: 100 * scale,
              ),
              child: Center(
                child: Text(
                  'No trips yet',
                  style: GoogleFonts.balooBhai2(
                    fontSize: 27 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.4),
                    height: 33 / 27,
                  ),
                ),
              ),
            ),

          // Loading state
          if (_isLoadingTrips)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 100 * scale),
              child: const Center(
                child: CircularProgressIndicator(
                  color: _dateBoxBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateForSearch(DateTime date) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${date.day} ${months[date.month - 1]}';
  }

  // ============================================================
  // FLIGHT TRACKING CONTENT - Exact Figma Layout
  // ============================================================

  Widget _buildFlightTrackingContent(double scale) {
    if (_selectedTrip == null || _selectedTrip!.flight == null) {
      return const SizedBox.shrink();
    }

    final flight = _selectedTrip!.flight!;
    final appendix = _trackingAppendix ?? _selectedTrip!.appendix;

    // Get data
    final originCity = appendix?.getAirport(flight.departureAirportFsCode)?.city ?? flight.departureAirportFsCode;
    final destCity = appendix?.getAirport(flight.arrivalAirportFsCode)?.city ?? flight.arrivalAirportFsCode;
    final airportName = appendix?.getAirport(flight.departureAirportFsCode)?.name ?? flight.departureAirportFsCode;
    final departureTerminal = _trackingFlightStatus?.airportResources?.departureTerminal ?? flight.departureTerminal;
    final departureGate = _trackingFlightStatus?.airportResources?.departureGate;
    final delayMinutes = _trackingFlightStatus?.delays?.departureGateDelayMinutes ?? 0;
    final hasDelay = delayMinutes > 0;
    final isOnTime = !hasDelay;
    final scheduledTime = flight.departureDateTime;
    final actualTime = _trackingFlightStatus?.operationalTimes?.scheduledGateDeparture?.localDateTime ?? scheduledTime;

    String formatDateShort(DateTime? dt) {
      if (dt == null) return '';
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]}';
    }

    String formatTime(DateTime? dt) {
      if (dt == null) return '--:--';
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========== HEADER SECTION ==========
          // Figma: Status circle at left:19, top:11, Close button at right:31
          Padding(
            padding: EdgeInsets.only(left: 19 * scale, right: 19 * scale, top: 11 * scale),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status circle - Figma: 73x73, inner ring 55x55
                Container(
                  width: 73 * scale,
                  height: 73 * scale,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 55 * scale,
                      height: 55 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isOnTime ? _onTimeGreen : _stepHighlightYellow,
                          width: 4 * scale,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          hasDelay ? '$delayMinutes' : '✓',
                          style: GoogleFonts.balooBhai2(
                            fontSize: hasDelay ? 43 * scale : 28 * scale,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Close button - Figma: SF Symbol at right:31
                GestureDetector(
                  onTap: _handleFlightTrackingBack,
                  child: Padding(
                    padding: EdgeInsets.only(top: 20 * scale, right: 12 * scale),
                    child: Icon(
                      CupertinoIcons.xmark,
                      size: 24 * scale,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ========== TITLE SECTION ==========
          // Figma: "Chandigarh to New York, 8 May" at left:19, fontSize:33
          Padding(
            padding: EdgeInsets.only(left: 19 * scale, right: 19 * scale, top: 15 * scale),
            child: Text(
              '$originCity to $destCity, ${formatDateShort(scheduledTime)}',
              style: GoogleFonts.balooBhai2(
                fontSize: 33 * scale,
                fontWeight: FontWeight.w500,
                color: Colors.black,
                height: 45 / 33,
              ),
            ),
          ),

          SizedBox(height: 30 * scale),

          // ========== PROGRESS STEPPER ==========
          // Figma positions: stepper at left:13, labels at left:69, badges at left:323

          // Step 1: Terminal/Airport
          _buildProgressStep(
            scale: scale,
            label: airportName,
            sublabel: 'Chhatrapati Shivaji Maharaj',
            badge: departureTerminal != null ? 'T$departureTerminal' : null,
            isFilled: true,
            isCurrent: false,
            isHighlighted: false,
            showLine: true,
          ),

          // Step 2: Gate
          _buildProgressStep(
            scale: scale,
            label: 'Your gate',
            sublabel: null,
            badge: departureGate,
            isFilled: true,
            isCurrent: false,
            isHighlighted: false,
            showLine: true,
          ),

          // Step 3: Delay/On time (highlighted if delay)
          _buildProgressStep(
            scale: scale,
            label: hasDelay ? '${delayMinutes}minute delay' : 'On time',
            sublabel: hasDelay ? 'R' : null,
            badge: null,
            timeBadgeOld: hasDelay ? formatTime(scheduledTime) : null,
            timeBadgeNew: hasDelay ? formatTime(actualTime) : null,
            isFilled: true,
            isCurrent: hasDelay,
            isHighlighted: hasDelay,
            showLine: true,
          ),

          // Step 4: Future step (empty)
          _buildProgressStep(
            scale: scale,
            label: '',
            sublabel: null,
            badge: null,
            isFilled: false,
            isCurrent: false,
            isHighlighted: false,
            showLine: false,
          ),

          SizedBox(height: 34 * scale + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  /// Builds a single progress step row matching exact Figma layout
  /// Figma positions: dot at x=13, label at x=69, badge at x=323
  Widget _buildProgressStep({
    required double scale,
    required String label,
    String? sublabel,
    String? badge,
    String? timeBadgeOld,
    String? timeBadgeNew,
    required bool isFilled,
    required bool isCurrent,
    required bool isHighlighted,
    required bool showLine,
  }) {
    // Figma measurements
    const double dotX = 13.0;        // Dot center X position
    const double labelX = 69.0;      // Label X position
    const double badgeX = 323.0;     // Badge X position
    const double dotSize = 17.0;     // Normal dot size
    const double currentDotSize = 24.0; // Current/highlighted dot size

    final actualDotSize = isCurrent ? currentDotSize : dotSize;
    final hasTimeBadge = timeBadgeOld != null && timeBadgeNew != null;

    // Row height based on content
    final rowHeight = sublabel != null ? 86.0 * scale : (label.isEmpty ? 40.0 * scale : 70.0 * scale);

    return Container(
      height: rowHeight,
      color: isHighlighted ? _stepHighlightYellow : Colors.transparent,
      child: Stack(
        children: [
          // Vertical connecting line
          if (showLine)
            Positioned(
              left: (dotX + dotSize / 2 - 1) * scale,
              top: (16 + actualDotSize) * scale,
              bottom: 0,
              child: Container(
                width: 2 * scale,
                color: _dotGray,
              ),
            ),

          // Dot
          Positioned(
            left: (dotX + (dotSize - actualDotSize) / 2) * scale,
            top: 16 * scale,
            child: Container(
              width: actualDotSize * scale,
              height: actualDotSize * scale,
              decoration: BoxDecoration(
                color: isCurrent
                    ? _stepHighlightYellow
                    : (isFilled ? Colors.black : _dotGray),
                shape: BoxShape.circle,
                border: isCurrent
                    ? Border.all(color: Colors.black, width: 3 * scale)
                    : null,
              ),
            ),
          ),

          // Label
          if (label.isNotEmpty)
            Positioned(
              left: labelX * scale,
              top: 12 * scale,
              right: (390 - badgeX + 19) * scale, // Leave space for badge
              child: Text(
                label,
                style: GoogleFonts.balooBhai2(
                  fontSize: 20 * scale,
                  fontWeight: FontWeight.w400,
                  color: Colors.black,
                  height: 27 / 20,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Sublabel
          if (sublabel != null)
            Positioned(
              left: labelX * scale,
              top: 40 * scale,
              child: Text(
                sublabel,
                style: GoogleFonts.balooBhai2(
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w400,
                  color: Colors.black.withValues(alpha: 0.6),
                  height: 24 / 17,
                ),
              ),
            ),

          // Badge (gray background) or Time badge (yellow background)
          if (hasTimeBadge)
            Positioned(
              right: 19 * scale,
              top: 12 * scale,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 5 * scale),
                decoration: BoxDecoration(
                  color: _stepHighlightYellow,
                  borderRadius: BorderRadius.circular(7 * scale),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeBadgeOld!,
                      style: GoogleFonts.balooBhai2(
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.6),
                        height: 25 / 17,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    SizedBox(width: 10 * scale),
                    Text(
                      timeBadgeNew!,
                      style: GoogleFonts.balooBhai2(
                        fontSize: 25 * scale,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        height: 31 / 25,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (badge != null)
            Positioned(
              left: badgeX * scale,
              top: 12 * scale,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 7 * scale),
                decoration: BoxDecoration(
                  color: _badgeBgGray,
                  borderRadius: BorderRadius.circular(7 * scale),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.balooBhai2(
                    fontSize: 25 * scale,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    height: 31 / 25,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTripCard(Trip trip, double scale, {required bool isUpcoming}) {
    // Figma: Upcoming cards are 96px, Previous cards are 109px
    final cardHeight = isUpcoming ? 96.0 * scale : 109.0 * scale;
    final dateBoxSize = 47.0 * scale;
    final statusBarHeight = 7.0 * scale;
    // Figma: Previous cards have trip info at top 28px, upcoming at top 22px
    final tripInfoTop = isUpcoming ? 22.0 * scale : 28.0 * scale;
    // Figma: Previous cards have date box at top 31px (within Date line container at top 19px + 12px offset)
    final dateBoxTop = isUpcoming ? 21.0 * scale : 31.0 * scale;

    return GestureDetector(
      onTap: () => _handleTripTap(trip),
      child: Container(
        height: cardHeight,
        width: double.infinity,
        color: isUpcoming ? Colors.white : _previousSectionBg,
        child: Stack(
          children: [
            // Date box with status bar
            Positioned(
              left: 17 * scale,
              top: dateBoxTop,
              child: Column(
                children: [
                  // Date box
                  Container(
                    width: dateBoxSize,
                    height: dateBoxSize,
                    decoration: BoxDecoration(
                      color: isUpcoming ? _dateBoxBlue : Colors.white,
                      borderRadius: BorderRadius.circular(0),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${trip.departureDateTime.day}',
                          style: GoogleFonts.balooBhai2(
                            fontSize: 27 * scale,
                            fontWeight: FontWeight.w600,
                            color: isUpcoming ? Colors.white : Colors.black,
                            height: 31 / 27,
                            letterSpacing: 0.81,
                          ),
                        ),
                        Text(
                          _formatMonth(trip.departureDateTime.month),
                          style: GoogleFonts.balooBhai2(
                            fontSize: 15 * scale,
                            fontWeight: FontWeight.w600,
                            color: isUpcoming ? Colors.white : Colors.black,
                            height: 21 / 15,
                            letterSpacing: 0.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status bar (only for upcoming trips)
                  if (isUpcoming)
                    Container(
                      width: dateBoxSize,
                      height: statusBarHeight,
                      color: trip.isDelayed ? _statusBarYellow : _statusBarGreen,
                    ),
                ],
              ),
            ),

            // Trip info
            Positioned(
              left: 85 * scale,
              top: tripInfoTop,
              child: SizedBox(
                width: 241 * scale,
                height: 51 * scale,
                child: Stack(
                  children: [
                    // Route: "City to City"
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Text(
                        '${trip.originCity} to ${trip.destinationCity}',
                        style: GoogleFonts.balooBhai2(
                          fontSize: 23 * scale,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                          height: 29 / 23,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Status (ON TIME / LATE) - only for upcoming trips
                    if (isUpcoming)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Text(
                          trip.isDelayed ? 'LATE' : 'ON TIME',
                          style: GoogleFonts.balooBhai2(
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.w700,
                            color: trip.isDelayed ? _lateTextYellow : _onTimeTextGreen,
                            height: 20 / 16,
                          ),
                        ),
                      ),
                    // Transport name (after status for upcoming, or at bottom for previous)
                    Positioned(
                      left: isUpcoming ? (trip.isDelayed ? 50 * scale : 70 * scale) : 0,
                      bottom: 0,
                      child: Text(
                        trip.transportName,
                        style: GoogleFonts.balooBhai2(
                          fontSize: isUpcoming ? 16 * scale : 14 * scale,
                          fontWeight: FontWeight.w500,
                          color: Colors.black.withValues(alpha: 0.6),
                          height: 20 / 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ============================================================
// DATE PICKER BOTTOM SHEET
// ============================================================

class _DatePickerBottomSheet extends StatefulWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const _DatePickerBottomSheet({
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<_DatePickerBottomSheet> createState() => _DatePickerBottomSheetState();
}

class _DatePickerBottomSheetState extends State<_DatePickerBottomSheet> {
  late DateTime _tempSelectedDate;

  @override
  void initState() {
    super.initState();
    _tempSelectedDate = widget.selectedDate;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = screenWidth / 390.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.only(top: 12 * scale),
            width: 36 * scale,
            height: 5 * scale,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2.5 * scale),
            ),
          ),

          // Header
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 19 * scale,
              vertical: 16 * scale,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.balooBhai2(
                      fontSize: 17 * scale,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF006ECF),
                      height: 23 / 17,
                    ),
                  ),
                ),
                Text(
                  'Select Date',
                  style: GoogleFonts.balooBhai2(
                    fontSize: 19 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    height: 25 / 19,
                  ),
                ),
                GestureDetector(
                  onTap: () => widget.onDateSelected(_tempSelectedDate),
                  child: Text(
                    'Done',
                    style: GoogleFonts.balooBhai2(
                      fontSize: 17 * scale,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF006ECF),
                      height: 23 / 17,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Container(
            height: 1,
            color: Colors.black.withValues(alpha: 0.1),
          ),

          // Date picker
          SizedBox(
            height: 216 * scale,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: _tempSelectedDate,
              minimumDate: DateTime.now().subtract(const Duration(days: 1)),
              maximumDate: DateTime.now().add(const Duration(days: 365)),
              onDateTimeChanged: (DateTime date) {
                setState(() {
                  _tempSelectedDate = date;
                });
              },
            ),
          ),

          SizedBox(height: bottomPadding + 16 * scale),
        ],
      ),
    );
  }
}
