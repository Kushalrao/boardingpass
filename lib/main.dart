import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'services/auth_service.dart';
import 'services/cirium_api_service.dart';
import 'models/schedule.dart';
import 'models/flight_status.dart';
import 'models/common.dart';

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
  List<({ScheduledFlight flight, Appendix? appendix})> _addedFlights = [];

  // Cape Town / Brackenfell area - default location from Figma
  static const LatLng _defaultLocation = LatLng(-33.8688, 18.7029);

  // Green accent color used throughout
  static const Color _accentGreen = Color(0xFF34C759);

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

  void _handleAcceptFlight() {
    if (_selectedResultIndex == null || _searchResults.isEmpty) return;
    
    final selectedFlight = _searchResults[_selectedResultIndex!];
    debugPrint('[Airtime] User accepted flight: ${selectedFlight.fullFlightNumber}');
    
    // Add the flight to added flights list
    setState(() {
      _addedFlights.add((flight: selectedFlight, appendix: _appendix));
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
      onTap: _handleAddFlightTap,
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
      onTap: onTap,
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
        
        return GestureDetector(
          onTap: () {
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
          ),
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
              onTap: _handleRejectFlight,
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
              onTap: _handleAcceptFlight,
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
  
  bool _isLoading = true;
  FlightStatus? _flightStatus;
  Appendix? _statusAppendix;

  // Colors from Figma
  static const Color _accentGreen = Color(0xFF34C759);
  static const Color _backgroundLight = Color(0xFFF1F5EB);
  static const Color _cardWhite = Color(0xFFFDFFFA);
  static const Color _flightBadgeBlue = Color(0xFF15357E);
  static const Color _flightBadgeTextBlue = Color(0xFFDCFBFF);
  static const Color _terminalRed = Color(0xFFFF383C);
  static const Color _gateGold = Color(0xFF6E5D1A);
  static const Color _gateTextGold = Color(0xFFFFFFDC);
  static const Color _beltNavy = Color(0xFF202269);
  static const Color _arrivalTimeBg = Color(0xFFE7EBD9);
  static const Color _aircraftBg = Colors.black;
  static const Color _aircraftText = Color(0xFFE7EBD9);

  @override
  void initState() {
    super.initState();
    _fetchFlightStatus();
  }

  Future<void> _fetchFlightStatus() async {
    setState(() {
      _isLoading = true;
    });

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
        setState(() {
          _flightStatus = response.flightStatuses.first;
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
      return _flightStatus!.operationalTimes?.scheduledGateDeparture?.localDateTime ??
             _flightStatus!.operationalTimes?.publishedDeparture?.localDateTime ??
             _flightStatus!.departureDate?.localDateTime;
    }
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
    _ciriumService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      body: Container(
        color: _backgroundLight,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _accentGreen))
            : SingleChildScrollView(
                child: SizedBox(
                  width: screenWidth,
                  // Height must accommodate all positioned children
                  // With stops: aircraft at 870 + 93 = 963, without: 719 + 93 = 812
                  // Add extra padding for safety
                  height: widget.flight.stops > 0 ? 1000 : 850,
                  child: Stack(
                    children: [
                      // Map at top
              SizedBox(
                        height: 386,
                        width: screenWidth,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _getDestinationLatLng(),
                            zoom: 10.0,
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
                      
                      // Back button - top left
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
                      
                      // Flight number badge
                      Positioned(
                        left: 24,
                        top: 244,
                        child: Container(
                          padding: const EdgeInsets.only(left: 9, right: 9, top: 9, bottom: 4),
                          decoration: BoxDecoration(
                            color: _flightBadgeBlue,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(
                            widget.flight.fullFlightNumber,
                            style: GoogleFonts.balooBhai2(
                              fontSize: 37,
                              fontWeight: FontWeight.w800,
                              color: _flightBadgeTextBlue,
                            ),
                          ),
                        ),
                      ),
                      
                      // Journey info card
                      Positioned(
                        left: 7,
                        top: 281,
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
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Departure info section
                      Positioned(
                        left: 0,
                        top: 386,
                        child: _buildDepartureSection(screenWidth),
                      ),
                      
                      // Stop info section (only if there are stops)
                      // Figma: top 572px, h 112px
                      if (widget.flight.stops > 0)
                        Positioned(
                          left: 0,
                          top: 572,
                          child: _buildStopSection(screenWidth),
                        ),
                      
                      // Arrival info section
                      // Figma: top 697px (with stop) or 559px (without stop), h 160px
                      Positioned(
                        left: 0,
                        top: widget.flight.stops > 0 ? 697 : 559,
                        child: _buildArrivalSection(screenWidth),
                      ),
                      
                      // Aircraft info section
                      // Figma: top 870px (with stop) or 719px (without stop), h 93px
                      if (_aircraftName != null || _aircraftCode != null)
                        Positioned(
                          left: 0,
                          top: widget.flight.stops > 0 ? 870 : 719,
                          child: _buildAircraftSection(screenWidth),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildDepartureSection(double screenWidth) {
    return Container(
      width: screenWidth,
      height: 173,
      color: _cardWhite,
      child: Stack(
        children: [
          // "Departure" title
          Positioned(
            left: 17,
            top: 17,
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
          // Airport name
          Positioned(
            left: 17,
            top: 50,
            child: SizedBox(
              width: 240,
              child: Text(
                _getDepartureAirportName(),
                style: GoogleFonts.balooBhai2(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  color: Colors.black,
                  height: 23 / 17,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Time box with green border
          Positioned(
            right: 13,
            top: 17,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _accentGreen, width: 4),
              ),
              child: Column(
                children: [
                  Text(
                    _formatTime(_departureTime),
                    style: GoogleFonts.balooBhai2(
                      fontSize: 31,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      letterSpacing: 2.17,
                      height: 45 / 31,
                    ),
                  ),
                  if (_isOnTime)
                    Container(
                      width: 80,
                      height: 27,
                      decoration: BoxDecoration(
                        color: _accentGreen,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(9),
                          bottomRight: Radius.circular(9),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'On Time',
                          style: GoogleFonts.balooBhai2(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                            color: _cardWhite,
                            letterSpacing: 1.19,
                            height: 23 / 17,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Terminal badge (if available)
          if (_departureTerminal != null)
            Positioned(
              left: 17,
              bottom: 13,
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
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      height: 33 / 23,
                    ),
                  ),
                ),
              ),
            ),
          // Gate badge (if available)
          if (_departureGate != null)
            Positioned(
              left: _departureTerminal != null ? 71 : 17,
              bottom: 13,
              child: Container(
                height: 33,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _gateGold,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.arrow_turn_up_right,
                      size: 19,
                      color: _gateTextGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Gate $_departureGate',
                      style: GoogleFonts.balooBhai2(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: _gateTextGold,
                        height: 33 / 23,
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

  Widget _buildStopSection(double screenWidth) {
    // Figma: icon at calc(50%-164.5px), title at calc(50%-138px)
    // For 390px width: icon at ~30px, title at ~57px
    return Container(
      width: screenWidth,
      height: 112,
      color: _backgroundLight,
      child: Stack(
        children: [
          // Stop icon - Figma: left calc(50%-164.5px)
          Positioned(
            left: 30,
            top: 33,
            child: Icon(
              CupertinoIcons.clock,
              size: 23,
              color: Colors.black,
            ),
          ),
          // Stop title - Figma: left calc(50%-138px), top 17px
          Positioned(
            left: 57,
            top: 17,
            child: Text(
              '${widget.flight.stops} stop${widget.flight.stops > 1 ? 's' : ''}',
              style: GoogleFonts.balooBhai2(
                fontSize: 25,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                height: 33 / 25,
              ),
            ),
          ),
          // Stop location - Figma: left calc(50%-138px), top 53px
          Positioned(
            left: 57,
            top: 53,
            child: SizedBox(
              width: 240,
              child: Text(
                'Connecting flight',
                style: GoogleFonts.balooBhai2(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  color: Colors.black,
                  height: 21 / 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrivalSection(double screenWidth) {
    return Container(
      width: screenWidth,
      height: 160,
      color: _cardWhite,
      child: Stack(
        children: [
          // "Arrival" title
          Positioned(
            left: 17,
            top: 15,
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
          // Airport name
          Positioned(
            left: 17,
            top: 49,
            child: SizedBox(
              width: 240,
              child: Text(
                _getArrivalAirportName(),
                style: GoogleFonts.balooBhai2(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  color: Colors.black,
                  height: 23 / 17,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Time box (gray background for arrival)
          Positioned(
            right: 13,
            top: 15,
            child: Container(
              width: 111,
              height: 45,
              decoration: BoxDecoration(
                color: _arrivalTimeBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  _formatTime(_arrivalTime),
                  style: GoogleFonts.balooBhai2(
                    fontSize: 31,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    letterSpacing: 2.17,
                    height: 45 / 31,
                  ),
                ),
              ),
            ),
          ),
          // Terminal badge (if available)
          if (_arrivalTerminal != null)
            Positioned(
              left: 17,
              bottom: 15,
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
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      height: 33 / 23,
                    ),
                  ),
                ),
              ),
            ),
          // Baggage belt badge (if available)
          if (_arrivalBaggage != null)
            Positioned(
              left: _arrivalTerminal != null ? 74 : 17,
              bottom: 15,
              child: Container(
                height: 33,
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 33 / 23,
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
    String? manufacturer;
    String? variant;
    
    if (_aircraftName != null) {
      final parts = _aircraftName!.split(' ');
      if (parts.isNotEmpty) manufacturer = parts[0];
      if (parts.length > 1) variant = parts.sublist(1).join(' ');
    }
    
    return Container(
      width: screenWidth,
      height: 93,
      color: _aircraftBg,
      child: Stack(
        children: [
          // Manufacturer name (e.g., "Boeing")
          Positioned(
            left: 16,
            top: 17,
            child: Text(
              manufacturer ?? _aircraftCode ?? '',
              style: GoogleFonts.balooBhai2(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                color: _aircraftText,
                height: 33 / 25,
              ),
            ),
          ),
          // Model code (e.g., "787")
          Positioned(
            right: 19,
            top: 17,
            child: Text(
              _aircraftCode ?? '',
              style: GoogleFonts.balooBhai2(
                fontSize: 23,
                fontWeight: FontWeight.w500,
                color: _aircraftText,
                letterSpacing: 4.6,
                height: 45 / 23,
              ),
            ),
          ),
          // Variant name (e.g., "Dreamliner")
          if (variant != null)
            Positioned(
              left: 16,
              top: 53,
              child: Text(
                variant,
                style: GoogleFonts.balooBhai2(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  color: const Color(0xFFFDFFFA).withValues(alpha: 0.6),
                  height: 23 / 17,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
