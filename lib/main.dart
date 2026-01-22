import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'services/auth_service.dart';
import 'services/cirium_api_service.dart';
import 'models/schedule.dart';
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
    
    // TODO: Add the flight to user's list (will be implemented later)
    // For now, just reset the state
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
                  child: (!_hasSearched || _searchResults.isEmpty) 
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
                    : const SizedBox.shrink(),
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
