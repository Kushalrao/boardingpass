# AIRTIME - Complete Project Context

> **Purpose of this file:** This is the single source of truth for any coding agent working on this project. Read this FIRST before exploring code. It contains the full architecture, every class, every method, every data flow, and every service — so you don't need to re-read the entire codebase each time.

---

## 1. WHAT IS AIRTIME?

Airtime is a **Flutter-based travel tracking application** that:
- Auto-imports flight bookings from Gmail using OpenAI extraction
- Tracks real-time flight status via the Cirium FlightStats API
- Sends push notifications for delays, gate changes, cancellations, diversions, baggage
- Supports manual flight addition and Indian Railways train tracking
- Targets iOS, Android, Web, and Desktop platforms

**Firebase Project ID:** `airtime-4e65f`
**Region:** `us-central1`

---

## 2. PROJECT STRUCTURE

```
/airtime/
├── lib/                              # Flutter/Dart app code
│   ├── main.dart                     # Entry point + HomePage + all UI (single-file app)
│   ├── models/
│   │   ├── common.dart               # Airline, Airport, Equipment, Codeshare, FlightDate, Appendix
│   │   ├── flight_status.dart        # FlightStatusResponse, FlightStatus, OperationalTimes, Delays, etc.
│   │   ├── schedule.dart             # ScheduleResponse, ScheduledFlight
│   │   ├── cirium_config.dart        # Cirium API configuration constants
│   │   ├── models.dart               # Barrel export
│   │   ├── user/app_user.dart        # AppUser model (Firestore-backed)
│   │   └── travel/
│   │       ├── booking_types.dart    # BookingType enum + all booking models (Flight, Hotel, Train, Bus, Event, Attraction, Visa, VacationRental)
│   │       ├── bookings.dart         # Base Booking class + FlightBooking, HotelBooking, etc.
│   │       └── travel_response.dart  # TravelAnalysisResponse
│   └── services/
│       ├── auth_service.dart         # Firebase Auth, Google Sign-In, flight CRUD, anonymous→Google migration
│       ├── cirium_api_service.dart   # Cirium FlightStats + Schedules API client
│       ├── notification_service.dart # FCM + local notifications
│       ├── flight_tracking_foreground_service.dart  # Android foreground service + custom RemoteViews notifications
│       ├── travel_service.dart       # Gmail travel extraction via Firebase Functions
│       └── services.dart             # Barrel export
├── functions/                        # Firebase Cloud Functions (Node.js/TypeScript)
│   ├── src/
│   │   ├── index.ts                  # All cloud function exports (921 lines)
│   │   ├── types/
│   │   │   ├── bookingTypes.ts       # TypeScript booking interfaces
│   │   │   └── schemas.ts           # OpenAI system prompts per booking type
│   │   ├── utils/
│   │   │   ├── emailQuery.ts         # Gmail search query (100+ travel domains)
│   │   │   └── bookingDetector.ts    # Booking type detection from email subject/sender
│   │   ├── services/
│   │   │   ├── gmailService.ts       # Gmail API client (fetch emails, PDFs)
│   │   │   ├── openaiService.ts      # OpenAI gpt-3.5-turbo extraction
│   │   │   ├── pdfService.ts         # PDF text extraction via pdf-parse
│   │   │   ├── gmailWatchService.ts  # Gmail push notification setup
│   │   │   ├── ciriumFlightStatusService.ts  # Flight status API
│   │   │   ├── ciriumRatingsService.ts       # Flight performance ratings
│   │   │   ├── ciriumWeatherService.ts       # Airport METAR/TAF weather
│   │   │   ├── ciriumEquipmentService.ts     # Aircraft equipment info
│   │   │   ├── ciriumAlertService.ts         # Flight alert subscriptions
│   │   │   └── fcmService.ts                 # Firebase Cloud Messaging sender
│   │   └── trains/
│   │       ├── index.ts              # Train cloud functions (524 lines)
│   │       ├── models/train.ts       # Train TypeScript interfaces
│   │       └── services/trainScraperService.ts  # HTTP client to Cloud Run scraper
│   ├── lib/                          # Compiled JS output (auto-generated from src/)
│   ├── package.json                  # Node.js deps: firebase-admin, firebase-functions, googleapis, openai, pdf-parse, axios
│   ├── tsconfig.json                 # TypeScript config (target: es2020, strict)
│   └── .env                          # Environment secrets (OPENAI_API_KEY, GOOGLE_CLIENT_ID/SECRET, CIRIUM_APP_ID/KEY, etc.)
├── train-scraper/                    # Python FastAPI microservice (deployed to Cloud Run)
│   ├── main.py                       # FastAPI endpoints: /health, /pnr/{pnr}, /schedule/{train}, /live/{train}, /search
│   ├── scrapers/
│   │   ├── pnr_status.py            # Selenium scraper for confirmtkt.com PNR status
│   │   ├── confirmtkt_scraper.py    # Selenium scraper for schedule, live status, search
│   │   └── ntes_scraper.py          # HTTP scrapers for erail.in, indiarailinfo.com, NTES
│   ├── requirements.txt             # fastapi, uvicorn, selenium, beautifulsoup4, httpx, pydantic
│   └── Dockerfile                   # Python 3.11-slim + Chromium for headless browser
├── android/
│   └── app/src/main/
│       ├── kotlin/com/example/airtime/
│       │   ├── MainActivity.kt               # MethodChannel for flight notifications
│       │   └── FlightNotificationHelper.kt   # Custom RemoteViews notification builder
│       └── res/
│           ├── layout/
│           │   ├── notification_flight_collapsed.xml  # Collapsed: flight path + airplane + status
│           │   └── notification_flight_expanded.xml   # Expanded: full flight tracker view
│           └── drawable/
│               ├── notification_flight_path.xml       # Thin green progress line
│               ├── notification_dot_green.xml         # Green endpoint dots
│               ├── notification_progress_bar.xml      # Standard green progress bar
│               └── ic_flight_progress.xml             # Airplane vector icon
├── ios/, web/, linux/, macos/, windows/  # Platform-specific code
├── assets/                           # Image assets
├── pubspec.yaml                      # Flutter deps
├── firebase.json                     # Firebase config
├── .firebaserc                       # Firebase project: airtime-4e65f
├── FIREBASE_ARCHITECTURE_PLAN.md     # Architecture design doc
├── GMAIL_OPENAI_INTEGRATION_PLAN.md  # Gmail+OpenAI integration plan
├── INBOUND_FLIGHT_TRACKING_PLAN.txt  # Inbound flight tracking feature spec
└── PRD_SCREEN_STATES.txt             # Full product requirements (1,045 lines, 41+ states)
```

---

## 3. TECH STACK

| Layer | Technology | Version |
|-------|-----------|---------|
| **Frontend** | Flutter/Dart | SDK ^3.8.1 |
| **Auth** | Firebase Auth + Google Sign-In | firebase_auth ^5.3.4, google_sign_in ^6.2.1 |
| **Database** | Cloud Firestore | cloud_firestore ^5.6.0 |
| **Backend Functions** | Firebase Cloud Functions (Node.js 20) | firebase-functions ^5.0.0 |
| **AI Extraction** | OpenAI GPT-3.5-turbo | openai ^4.20.0 |
| **Flight Data** | Cirium FlightStats API | REST API v2 |
| **Push Notifications** | Firebase Cloud Messaging | firebase_messaging ^15.1.6 |
| **Maps** | Google Maps Flutter | google_maps_flutter ^2.6.1 |
| **Live Flight Notifications** | Android Custom RemoteViews + MethodChannel | Native Kotlin + DecoratedCustomViewStyle |
| **Train Data** | Custom Python scraper on Cloud Run | FastAPI + Selenium + BeautifulSoup |
| **PDF Parsing** | pdf-parse (Node.js) | ^1.1.1 |
| **Email** | Gmail API via googleapis | ^140.0.0 |

---

## 4. ENVIRONMENT VARIABLES & API CREDENTIALS

**Location:** `functions/.env`

| Variable | Purpose |
|----------|---------|
| `OPENAI_API_KEY` | OpenAI GPT-3.5-turbo for booking extraction |
| `GOOGLE_CLIENT_ID` | OAuth for Google Sign-In (web client) |
| `GOOGLE_CLIENT_SECRET` | OAuth secret |
| `GMAIL_PUBSUB_TOPIC` | `projects/airtime-4e65f/topics/gmail-notifications` |
| `CIRIUM_APP_ID` | `5aae456b` - Cirium FlightStats API |
| `CIRIUM_APP_KEY` | `b5da0595ab863d6421f5e66b73805e0b` - Cirium FlightStats API |
| `CIRIUM_WEBHOOK_URL` | `https://us-central1-airtime-4e65f.cloudfunctions.net/ciriumAlertWebhook` |
| `TRAIN_SCRAPER_URL` | Cloud Run URL for train scraper service |

**Flutter-side credentials (hardcoded in code):**
- Cirium: In `lib/services/cirium_api_service.dart` (appId + appKey)
- Google OAuth: In `lib/services/auth_service.dart` (web + iOS client IDs)

---

## 5. FIREBASE CLOUD FUNCTIONS — COMPLETE LIST

### Flight Functions (in `functions/src/index.ts`)

| Function | Type | Auth | Purpose |
|----------|------|------|---------|
| `analyzeTravel` | Callable | Yes | Fetch Gmail emails → detect booking type → extract PDF/body → OpenAI extraction → return structured bookings |
| `storeRefreshToken` | Callable | Yes | Exchange Google auth code for refresh token, store in Firestore |
| `setupGmailWatch` | Callable | Yes | Set up Gmail push notifications via Pub/Sub |
| `gmailWebhook` | Pub/Sub trigger | N/A | Process new Gmail messages automatically when they arrive |
| `ciriumAlertWebhook` | HTTPS POST | N/A | Receive Cirium flight status updates → notify users via FCM |
| `createFlightAlert` | Callable | Yes | Subscribe to Cirium alerts for a flight |
| `deleteFlightAlert` | Callable | Yes | Unsubscribe from Cirium alerts |
| `onFlightCreated` | Firestore trigger | N/A | On new flight doc: fetch Cirium data (status, ratings, weather, equipment), create alert, send FCM |
| `onFlightDeleted` | Firestore trigger | N/A | On flight deletion: delete associated Cirium alert |

### Train Functions (in `functions/src/trains/index.ts`)

| Function | Type | Auth | Purpose |
|----------|------|------|---------|
| `getTrainPnrStatus` | Callable | No | Fetch PNR status from train scraper |
| `getTrainSchedule` | Callable | No | Fetch train schedule |
| `getTrainLiveStatus` | Callable | No | Fetch live running status |
| `searchTrains` | Callable | No | Search trains between stations |
| `addTrainBooking` | Callable | Yes | Add train booking (by PNR or train number) |
| `getUserTrains` | Callable | Yes | Get user's train bookings |
| `refreshTrainStatus` | Callable | Yes | Refresh PNR/live status for a booking |
| `deleteTrainBooking` | Callable | Yes | Delete a train booking |
| `onTrainCreated` | Firestore trigger | N/A | Log train creation |

---

## 6. FIRESTORE DATA STRUCTURE

```
users/{userId}
├── uid: string
├── email: string
├── displayName: string
├── photoUrl: string
├── createdAt: Timestamp
├── lastLoginAt: Timestamp
├── isAnonymous: boolean
├── gmailRefreshToken: string          # For backend Gmail access
├── gmailTokenUpdatedAt: Timestamp
├── gmailWatchHistoryId: string        # For Gmail push notifications
├── gmailWatchExpiration: string
├── gmailWatchSetupAt: Timestamp
├── fcmTokens: Array<{token, platform, createdAt}>
│
├── flights/{flightId}                 # Subcollection
│   ├── carrierFsCode: "LX"
│   ├── flightNumber: "147"
│   ├── fullFlightNumber: "LX147"
│   ├── departureTime: ISO string
│   ├── arrivalTime: ISO string
│   ├── originAirport: "DEL"
│   ├── destinationAirport: "ZRH"
│   ├── originCity: "Delhi"
│   ├── destinationCity: "Zurich"
│   ├── airlineName: "Swiss"
│   ├── originAirportName: string
│   ├── destinationAirportName: string
│   ├── stops: number
│   ├── departureTerminal: "3"
│   ├── arrivalTerminal: "2"
│   ├── flightEquipmentIataCode: "333"
│   ├── serviceClasses: string[]
│   ├── isCodeshare: boolean
│   ├── isWetlease: boolean
│   ├── addedAt: Timestamp
│   ├── source: "manual" | "gmail"
│   │
│   │   // Enriched by onFlightCreated trigger:
│   ├── performanceRating: {observations, ontimePercent, late15, late30, late45, cancelled, diverted, delayMean, delayMax, stars, fetchedAt}
│   ├── flightStatus: {status, airlineName, departureTerminal, departureGate, arrivalTerminal, arrivalGate, baggageBelt, scheduledDeparture, estimatedDeparture, actualDeparture, scheduledArrival, estimatedArrival, actualArrival, departureDelayMinutes, arrivalDelayMinutes, flightDurationMinutes, equipmentCode, equipmentName, isWidebody, tailNumber, codeshares, fetchedAt}
│   ├── equipment: {iataCode, name, type, isJet, isWidebody, isTurboProp, isRegional, fetchedAt}
│   ├── weather: {departure: {...}, arrival: {...}}  # METAR data per airport
│   ├── ciriumAlertRuleId: string
│   ├── ciriumAlertCreatedAt: Timestamp
│   ├── alertCapabilities: {baggage, departureGateChange, arrivalGateChange, ...}
│   ├── lastAlertType: string
│   ├── lastAlertAt: Timestamp
│   └── lastAlertDetails: {...}
│
├── travels/{messageId}                # Subcollection (from Gmail extraction)
│   ├── booking_type: "flight" | "hotel" | "train" | "bus" | "event" | "attraction" | "visa" | "vacation_rental"
│   ├── booking_reference: string
│   ├── date: string (email date)
│   ├── origin: string
│   ├── destination: string
│   ├── amount: number
│   ├── currency: string
│   ├── amountINR: number
│   ├── pdfParseStatus: "success" | "error" | "email_body" | "not_attempted"
│   ├── emailMessageId: string
│   ├── source: "webhook" | "manual"
│   ├── createdAt: Timestamp
│   ├── savedAt: Timestamp
│   └── ... (booking-type-specific fields like passengers, flights, hotel_name, etc.)
│
└── trains/{trainId}                   # Subcollection
    ├── trainNumber: string
    ├── trainName: string
    ├── pnr: string
    ├── journeyDate: string
    ├── fromStation: {code, name, time}
    ├── toStation: {code, name, time}
    ├── travelClass: string
    ├── passengers: Array<{number, bookingStatus, currentStatus, coach, berth}>
    ├── chartStatus: string
    ├── overallStatus: string
    ├── confirmationChance: string
    ├── liveStatus: {...}
    ├── source: "manual"
    ├── addedAt: Timestamp
    └── lastChecked: Timestamp
```

---

## 7. CIRIUM FLIGHTSTATS API — ALL ENDPOINTS USED

**Base:** `https://api.flightstats.com/flex`

| Service | Endpoint | Purpose |
|---------|----------|---------|
| **Flight Status** | `/flightstatus/rest/v2/json/flight/status/{carrier}/{flightNumber}/dep/{year}/{month}/{day}` | Get status by flight + date |
| **Flight Status by Route** | `/flightstatus/rest/v2/json/route/status/{depAirport}/{arrAirport}/dep/{year}/{month}/{day}` | All flights on route |
| **Schedules** | `/schedules/rest/v1/json/flight/{carrier}/{flightNumber}/departing/{year}/{month}/{day}` | Schedule by flight |
| **Schedules by Route** | `/schedules/rest/v1/json/from/{depAirport}/to/{arrAirport}/departing/{year}/{month}/{day}` | Schedules on route |
| **Ratings** | `/ratings/rest/v1/json/flight/{carrier}/{flightNumber}` | Performance ratings (on-time %, delays) |
| **Route Ratings** | `/ratings/rest/v1/json/route/{depAirport}/{arrAirport}` | All flights on route rated |
| **Weather** | `/weather/rest/v1/json/all/{airportCode}` | METAR + TAF weather data |
| **Equipment** | `/equipment/rest/v1/json/iata/{iataCode}` | Aircraft type info |
| **Alerts Create** | `/alerts/rest/v1/json/create/{carrier}/{flightNumber}/from/{depAirport}/departing/{year}/{month}/{day}` | Subscribe to status updates |
| **Alerts Delete** | `/alerts/rest/v1/json/delete/{ruleId}` | Unsubscribe |
| **Alerts List** | `/alerts/rest/v1/json/list` | List active alerts |
| **Alerts Get** | `/alerts/rest/v1/json/get/{ruleId}` | Get alert details |

**All requests require `?appId=...&appKey=...` query params.**

**Flight Status Codes:** `S` (Scheduled), `A` (Active/In-flight), `L` (Landed), `C` (Cancelled), `D` (Diverted), `R` (Redirected), `U` (Unknown), `NO` (Not Operational)

---

## 8. FLUTTER APP — DETAILED ARCHITECTURE

### 8.1 Entry Point (`lib/main.dart`)

The entire UI is in a single file (~1800+ lines). It uses **StatefulWidget with TickerProviderStateMixin** — no third-party state management.

**App Initialization:**
1. Google Maps Flutter initialization (Android renderer)
2. Firebase initialization
3. FCM background handler registration
4. Run `MyApp` → `MaterialApp` → `HomePage`

### 8.2 Screen Modes

The app has 3 mutually exclusive modes controlled by state booleans:

| Mode | State Variable | What's Shown |
|------|---------------|-------------|
| **Home** | default | Google Map (top) + trip list (Next Up / Previous) |
| **Search** | `_isSearchMode = true` | Search input + date picker overlay |
| **Flight Tracking** | `_isFlightTrackingMode = true` | Status circle + stepper with gate/delay/terminal info |

**Mode Transitions:**
- Home → Search: User taps search bar
- Home → Flight Tracking: User taps a trip card
- Search/Tracking → Home: User taps back button

### 8.3 State Variables

```dart
// Services
AuthService _authService;
CiriumApiService _ciriumService;

// Trip data
List<Trip> _trips = [];
bool _isLoadingTrips = false;

// Search mode
bool _isSearchMode = false;
TextEditingController _searchController;
String _searchQuery = '';
bool _showDatePicker = false;
DateTime _selectedDate = DateTime.now();

// Flight tracking mode
bool _isFlightTrackingMode = false;
Trip? _selectedTrip;
FlightStatus? _trackingFlightStatus;
Appendix? _trackingAppendix;

// Animation controllers (3)
AnimationController _searchAnimationController;
AnimationController _datePickerAnimationController;
AnimationController _flightTrackingAnimationController;

// Map
GoogleMapController? _mapController;
```

### 8.4 Trip Model

```dart
enum TripType { flight, train }

class Trip {
  final TripType type;
  final String id;
  final DateTime departureDateTime;
  final DateTime? arrivalDateTime;
  final String originCity;
  final String destinationCity;
  final String transportName;      // "Air India AI2447" or "Rajdhani Express"
  final bool isDelayed;
  final int? delayMinutes;
  final ScheduledFlight? flight;   // Only for TripType.flight
  final Appendix? appendix;
  final String? firestoreId;

  bool get isUpcoming => departureDateTime.isAfter(DateTime.now());
}
```

### 8.5 Key UI Methods

| Method | Purpose |
|--------|---------|
| `_loadTrips()` | Loads flights from Firestore, converts to Trip objects |
| `_checkDelaysForTrips()` | Background: fetches Cirium status for each trip, updates delay info |
| `_fetchTrackingFlightStatus(trip)` | Fetches full Cirium status when user taps a trip |
| `_handleSearchTap()` | Enters search mode with animation |
| `_handleSearchBack()` | Exits search mode |
| `_handleTripTap(trip)` | Enters flight tracking mode |
| `_handleFlightTrackingBack()` | Exits tracking mode |
| `_buildTripsOnlyContent(scale)` | Renders home screen trip list |
| `_buildFlightTrackingContent(scale)` | Renders tracking stepper UI |
| `_buildTripCard(trip, scale, isUpcoming)` | Renders individual trip card |
| `_buildProgressStep(...)` | Renders one step in the tracking stepper |

### 8.6 Animation System

- **Duration:** 280ms, `Curves.easeOutQuart`
- **Pattern:** Slide (20% of width) + Fade
- Date picker width animates when search input matches flight/train pattern
- Regex patterns: Flight = `^[A-Za-z]{2,3}\d+$`, Train = `^\d{5}$`

### 8.7 Design System

| Token | Value |
|-------|-------|
| Background | `#F0F0E1` (light cream) |
| Search bar bg | `#EEF0EB` |
| Previous section bg | `#F5F7F2` |
| Date box blue | `#006ECF` |
| On-time green | `#00E439` / `#05B331` / `#34C759` |
| Late yellow | `#FFBF00` / `#CA9805` / `#FFCC00` |
| Badge bg | `#F5F7F2` |
| Dot gray | `#E0E0E0` |
| Font | Baloo Bhai 2 (Google Fonts) |
| Figma reference width | 390px (responsive scaling: `scale = screenWidth / 390`) |
| Map height | 404px (at 390px width) |

---

## 9. FLUTTER SERVICES — DETAILED

### 9.1 AuthService (`lib/services/auth_service.dart`)

**Google OAuth Scopes:** `email`, `profile`, `https://www.googleapis.com/auth/gmail.readonly`

**Key Properties:**
- `firebaseUser`, `currentUser`, `isSignedIn`, `hasAuth`, `isAnonymous`, `userId`
- `authStateChanges` stream

**Key Methods:**

| Method | What It Does |
|--------|-------------|
| `init()` | Initialize auth, create anonymous account if needed, load user from Firestore |
| `signInWithGoogle()` | Full Google Sign-In → link anonymous account → migrate flights → store refresh token → setup Gmail watch |
| `_migrateFlightsFromAnonymous(anonUid, googleUid)` | Copy flights from anonymous to Google account, deduplicate, delete anonymous data |
| `_createOrUpdateUser(firebaseUser, googleUser)` | Create/update user doc in Firestore |
| `signOut()` | Google + Firebase sign out |
| `getGmailAccessToken()` | Returns current Google OAuth access token |
| `getIdToken()` | Returns Firebase ID token |
| `saveFlight(data)` | Add flight to `users/{uid}/flights` |
| `loadFlights()` | Get all flights ordered by addedAt desc |
| `deleteFlight(id)` | Delete a flight doc |

### 9.2 CiriumApiService (`lib/services/cirium_api_service.dart`)

**Credentials:** `appId = '5aae456b'`, `appKey = 'b5da0595ab863d6421f5e66b73805e0b'`

| Method | Endpoint Pattern | Returns |
|--------|-----------------|---------|
| `getFlightStatus(carrier, number, year, month, day)` | `/flight/status/{carrier}/{number}/dep/{y}/{m}/{d}` | `FlightStatusResponse` |
| `getFlightStatusToday(carrier, number)` | Same with today's date | `FlightStatusResponse` |
| `getFlightStatusByRoute(dep, arr, date)` | `/route/status/{dep}/{arr}/dep/{date}` | `FlightStatusResponse` |
| `getSchedule(carrier, number, date)` | `/flight/{carrier}/{number}/departing/{date}` | `ScheduleResponse` |
| `getScheduleByRoute(dep, arr, date)` | `/from/{dep}/to/{arr}/departing/{date}` | `ScheduleResponse` |
| `getScheduleByDepartureAirport(airport, date)` | `/from/{airport}/departing/{date}` | `ScheduleResponse` |
| `getScheduleByArrivalAirport(airport, date)` | `/to/{airport}/arriving/{date}` | `ScheduleResponse` |
| `parseFlightNumber(flight)` | Parses "LX147" → `{carrier: "LX", number: "147"}` | Map |
| `getFlightStatusByFlightNumber(flight, date)` | Auto-parsing wrapper | `FlightStatusResponse` |
| `getScheduleByFlightNumber(flight, date)` | Auto-parsing wrapper | `ScheduleResponse` |

### 9.3 NotificationService (`lib/services/notification_service.dart`)

Singleton. Android channel: `flight_status` (high importance).

| Method | Purpose |
|--------|---------|
| `init(userId)` | Request permissions, init local notifications, get/store FCM token, set up message handlers |
| `_onForegroundMessage(msg)` | Show local notification when app is in foreground |
| `_onMessageOpenedApp(msg)` | Handle notification tap (app was in background) |
| `_storeToken(token)` | Store FCM token in Firestore `users/{uid}.fcmTokens` |
| `cleanup()` | Remove FCM token from Firestore on sign out |

### 9.4 FlightTrackingForegroundService (`lib/services/flight_tracking_foreground_service.dart`)

Singleton. Android-only. Manages persistent foreground service + custom RemoteViews notifications for live flight tracking.

**Notification Channels:**
- `flight_tracking_service` (LOW importance) — foreground service keepalive
- `flight_tracking_live` (LOW importance) — per-flight custom notifications

**Key Classes:**
- `FlightTrackingData` — DTO passed from `main.dart` (firestoreId, flightNumber, originCity, destinationCity, departureDateTime, arrivalDateTime, departureTerminal, arrivalTerminal, gate)
- `_TrackedFlight` — internal mutable state (status, gate, delayMinutes, diversionAirport, baggageBelt)
- `_FlightTrackingTaskHandler` — top-level foreground task callback (no-op, updates via FCM)

**Key Methods:**

| Method | Purpose |
|--------|---------|
| `init()` | Configure foreground task, create notification channel, start FCM listener |
| `evaluateFlights(flights)` | Filter flights eligible for tracking (departed or departing within 24h), start service |
| `_showFlightNotification(id)` | Compute phase (pre-departure/in-flight/landed/cancelled/diverted), invoke MethodChannel |
| `_handleFcmMessage(msg)` | Update tracked flight state from FCM event, re-render notification |
| `_stopTrackingFlight(id)` | Cancel notification, remove from map, stop service if empty |
| `_scheduleRemoval(id)` | Auto-remove 30 min after landing |

**MethodChannel:** `com.example.airtime/flight_notification` — communicates with native `FlightNotificationHelper.kt` for custom RemoteViews rendering. See Section 13.5 for full architecture details.

### 9.5 TravelService (`lib/services/travel_service.dart`)

| Method | Purpose |
|--------|---------|
| `analyzeTravel(batchSize, batch, year, saveToFirestore)` | Calls Firebase Function `analyzeTravel`, parses response into `TravelAnalysisResponse` |
| `analyzeAllTravel(batchSize, year, saveToFirestore, onProgress)` | Iterates through all batches until `moreBatches=false` |
| `_saveTravelsToFirestore(travels)` | Batch write travels to `users/{uid}/travels` |
| `getSavedTravels(limit, bookingType)` | Query saved travels from Firestore |
| `getTravelStats()` | Calculate trip counts and total INR spend |
| `deleteTravel(id)` | Delete a travel record |

---

## 10. FLUTTER DATA MODELS — COMPLETE

### 10.1 Common Models (`lib/models/common.dart`)

```
Airline: {fs, iata, icao, name, active, category}
Airport: {fs, iata, icao, name, city, cityCode, countryCode, countryName, regionName, timeZoneRegionName, utcOffsetHours, latitude, longitude, elevationFeet, classification, active}
Equipment: {iata, name, turboProp, jet, widebody, regional}
Codeshare: {fsCode, flightNumber, relationship, serviceType, serviceClasses, trafficRestrictions}
FlightDate: {dateUtc, dateLocal} + getters: utcDateTime, localDateTime
Appendix: {airlines[], airports[], equipments[]} + getters: getAirline(fs), getAirport(fs), getEquipment(iata)
```

### 10.2 FlightStatus Models (`lib/models/flight_status.dart`)

```
FlightStatusResponse: {request?, flightStatuses[], appendix?, error?}
FlightStatus: {flightId, carrierFsCode, operatingCarrierFsCode, flightNumber, departureAirportFsCode, arrivalAirportFsCode, departureDate, arrivalDate, status, schedule, operationalTimes, codeshares[], delays, flightDurations, airportResources, flightEquipment, irregularOperations[]}
  - statusText getter: maps S/A/L/C/D/R/U/NO to human-readable
  - fullFlightNumber getter: "LX147"
OperationalTimes: {publishedDeparture, scheduledGateDeparture, estimatedGateDeparture, actualGateDeparture, scheduledGateArrival, estimatedGateArrival, actualGateArrival, estimatedRunwayDeparture, actualRunwayDeparture, estimatedRunwayArrival, actualRunwayArrival}
Delays: {departureGateDelayMinutes, departureRunwayDelayMinutes, arrivalGateDelayMinutes, arrivalRunwayDelayMinutes} + hasDepartureDelay, hasArrivalDelay
AirportResources: {departureTerminal, departureGate, arrivalTerminal, arrivalGate, baggage}
FlightEquipment: {scheduledEquipmentIataCode, actualEquipmentIataCode, tailNumber, fleetAircraftId}
FlightDurations: {scheduledBlockMinutes, blockMinutes, airMinutes, taxiOutMinutes, taxiInMinutes} + scheduledDuration, actualDuration (as Duration)
IrregularOperation: {type, newArrivalAirportFsCode, dateUtc, dateLocal}
```

### 10.3 Schedule Models (`lib/models/schedule.dart`)

```
ScheduleResponse: {request?, scheduledFlights[], appendix?, error?}
ScheduledFlight: {carrierFsCode, flightNumber, departureAirportFsCode, arrivalAirportFsCode, departureTime, arrivalTime, stops, departureTerminal, arrivalTerminal, flightEquipmentIataCode, isCodeshare, isWetlease, serviceType, serviceClasses[], trafficRestrictions[], codeshares[], referenceCode}
  - fullFlightNumber getter
  - departureDateTime, arrivalDateTime getters
  - isNonStop getter
  - serviceTypeDescription getter (maps J/F/G/H/P to human-readable)
```

### 10.4 Booking Models (`lib/models/travel/`)

**BookingType enum:** `flight, hotel, train, bus, event, attraction, visa, vacationRental`

**Base Booking (abstract):** bookingType, bookingReference, bookingDate, status, contactInformation, date, pdfParseStatus, pdfParseError, origin, destination, amount, currency, amountINR, emailMessageId, confirmationNumber

**FlightBooking:** airline, tripType, totalAmountPaid, passengers[], flights[] (FlightSegment), fareBreakdown, additionalInfo
**HotelBooking:** hotelName, hotelBrand, address, checkIn, checkOut, nights, roomDetails, guests[], totalAmount, amenities[], cancellationPolicy
**TrainBooking:** pnr, trainNumber, trainName, departure, arrival, duration, trainClass, coach, seatBerth, passengers[], totalAmount
**BusBooking:** busOperator, busType, departure, arrival, duration, seatNumbers[], passengers[], totalAmount, boardingPoint, droppingPoint
**EventBooking:** eventName, eventType, venue, eventDate, numberOfTickets, totalAmount
**AttractionBooking:** attractionName, attractionType, location, visitDate, visitTime, duration, totalAmount
**VisaBooking:** applicationReference, applicationDate, visaType, country, applicant, visaDetails, appointment, fees
**VacationRentalBooking:** propertyName, propertyType, hostName, address, checkIn, checkOut, nights, guests, totalAmount, amenities[], houseRules, cancellationPolicy

**Supporting:** Amount, ContactInformation, Address, Passenger, FareBreakdown, FlightSegment, FlightLocation

---

## 11. BACKEND DATA PIPELINES

### Pipeline A: Manual `analyzeTravel` (User-triggered)

```
User taps "Analyze" → Flutter calls analyzeTravel Firebase Function
  → GmailService.fetchTravelEmails(accessToken, batchSize, batch, year)
    → Gmail API: list messages matching travel query (100+ domains)
    → Paginate (500 per page), filter by year
    → For each email in batch: fetch full message, extract headers + body + PDF attachments
  → For each email:
    → bookingDetector.detectBookingType(subject, from) → only process 'flight'
    → If PDF: PdfService.extractText(pdfBuffer) → text
    → Else: use email body text
    → OpenAIService.extractBookingData(text, 'flight')
      → gpt-3.5-turbo (temperature=0, max_tokens=1500)
      → System prompt from SYSTEM_PROMPTS['flight']
      → Parse JSON from response
    → Extract origin, destination, amount, currency
    → convertToINR(amount, currency) using fixed rates (USD=83, EUR=90, GBP=105)
  → Return {travels[], moreBatches, nextBatch, totalEmails}
```

### Pipeline B: Gmail Webhook (Automatic)

```
New email arrives → Gmail Pub/Sub notification → gmailWebhook trigger
  → Decode emailAddress from Pub/Sub message
  → Find user by email in Firestore
  → GmailWatchService.getNewMessages(userId, lastHistoryId)
    → Gmail API: history.list since lastHistoryId
    → Collect new message IDs
  → For each message:
    → Fetch full message → detect booking type → extract content
    → OpenAI extraction → optionally fetch Cirium ratings
    → Store in users/{userId}/travels/{messageId}
  → Update gmailWatchHistoryId
```

### Pipeline C: Flight Created (Firestore trigger)

```
Flight doc created in users/{userId}/flights/{flightId}
  → Send FCM "Flight Added" notification
  → Parallel Cirium API calls:
    1. CiriumRatingsService.getFlightRatings() → performanceRating
    2. CiriumFlightStatusService.getFlightStatus() → flightStatus + equipment code
    3. CiriumEquipmentService.getEquipment(code) → equipment info
    4. CiriumWeatherService.getAirportWeather(depAirport) → weather.departure
    5. CiriumWeatherService.getAirportWeather(arrAirport) → weather.arrival
  → Update flight doc with all enrichment data
  → CiriumAlertService.createAlert() → store ciriumAlertRuleId
```

### Pipeline D: Cirium Alert Webhook (Flight status changes)

```
Cirium POSTs to ciriumAlertWebhook
  → Parse event type: DEPARTURE | ARRIVAL | DELAY | CANCELLATION | DIVERSION | GATE_CHANGE | BAGGAGE
  → Query all flights with matching ciriumAlertRuleId
  → For each user tracking this flight:
    → FcmService.formatFlightStatusNotification() → title + body + data
    → FcmService.sendToUser(userId, notification)
  → Update flight doc: lastAlertType, lastAlertAt, lastAlertDetails
```

---

## 12. TRAIN SCRAPER SERVICE (Cloud Run)

**Deployed URL:** Cloud Run (Google Cloud)
**Framework:** FastAPI (Python 3.11)
**Scraping:** Selenium (headless Chromium) + BeautifulSoup + HTTP clients

| Endpoint | Method | Source | Purpose |
|----------|--------|--------|---------|
| `/health` | GET | N/A | Health check |
| `/pnr/{pnr}` | GET | confirmtkt.com (Selenium) | PNR status with passenger details |
| `/schedule/{train}` | GET | confirmtkt.com (Selenium) | Full station-wise schedule |
| `/live/{train}` | GET | confirmtkt.com (Selenium) | Live running status with delays |
| `/search` | GET | erail.in (HTTP) | Search trains between stations |

**Data Sources (multiple scrapers with fallbacks):**
1. **ConfirmTkt** (Selenium): PNR, schedule, live status, search
2. **erail.in** (HTTP): Train info, search, fares, seat availability, station board
3. **indiarailinfo.com** (HTTP): Schedule, search (fallback)
4. **NTES** (HTTP): Live status, schedule (fallback)

**Built-in fare calculation** for Rajdhani, Shatabdi, Vande Bharat, Duronto, Garib Rath, Mail/Express with class-wise rates.

---

## 13. NOTIFICATION SYSTEM

### FCM Channel (Push Notifications)
- **Channel ID:** `flight_status`
- **Channel Name:** `Flight Status`
- **Importance:** High
- **Platform configs:** Android (high priority, channelId) + iOS (default sound, badge=1)

### FCM Notification Types

| Event | Title | Body Example |
|-------|-------|-------------|
| Flight Added | "Flight Added" | "We found your AI111 flight from Delhi to London on 2024-02-15" |
| Departure | "AI111 Departed" | "Your flight has departed from DEL" |
| Arrival | "AI111 Arrived" | "Your flight has arrived at LHR" |
| Delay | "AI111 Delayed" | "Your flight is delayed by 45 minutes" |
| Gate Change | "AI111 Gate Change" | "Gate changed to A5" |
| Cancellation | "AI111 Cancelled" | "Your flight has been cancelled" |
| Diversion | "AI111 Diverted" | "Your flight is being diverted to BOM" |
| Baggage | "AI111 Baggage Info" | "Collect your baggage at belt 12" |

### Token Management
- Tokens stored in `users/{uid}.fcmTokens` array
- Invalid tokens auto-cleaned on send failure
- Token refresh handled via `onTokenRefresh` listener

---

## 13.5. ANDROID LIVE FLIGHT TRACKING (Custom RemoteViews Notifications)

Android-only persistent notifications that display real-time flight status using custom RemoteViews layouts, similar to iOS Live Activities. Bypasses `flutter_local_notifications` for the tracking notification to enable full control over layout, colors, and progress bar styling.

### Architecture Overview

```
Flutter (Dart)                         Android (Kotlin)
┌──────────────────────────┐           ┌──────────────────────────────┐
│ FlightTrackingForeground │           │ MainActivity                 │
│ Service                  │──────────▶│   MethodChannel handler      │
│                          │ invoke    │   ↓                          │
│ _showFlightNotification()│ Method    │ FlightNotificationHelper     │
│ _channel.invokeMethod()  │ Channel   │   .show(params)              │
│                          │           │   .cancel(id)                │
│ Phase logic (Dart-side): │           │   ↓                          │
│ - Pre-departure          │           │ NotificationCompat.Builder   │
│ - In Flight              │           │   + DecoratedCustomViewStyle │
│ - Landed                 │           │   + collapsed RemoteViews    │
│ - Cancelled              │           │   + expanded RemoteViews     │
│ - Diverted               │           └──────────────────────────────┘
└──────────────────────────┘
```

**MethodChannel:** `com.example.airtime/flight_notification`
- `showFlightNotification` — receives Map of params, delegates to `FlightNotificationHelper.show()`
- `cancelFlightNotification` — cancels notification by ID

### Files

| File | Purpose |
|------|---------|
| `android/.../kotlin/.../MainActivity.kt` | MethodChannel setup, routes calls to helper |
| `android/.../kotlin/.../FlightNotificationHelper.kt` | Builds collapsed + expanded RemoteViews, shows notification via `NotificationManagerCompat` |
| `android/.../res/layout/notification_flight_collapsed.xml` | Collapsed view: flight path with city names, green dots, progress bar, airplane icon, status, subtitle |
| `android/.../res/layout/notification_flight_expanded.xml` | Expanded view: flight number, departure/arrival times+cities, flight path, status, time remaining, details |
| `android/.../res/drawable/notification_flight_path.xml` | Thin line progress drawable (green `#4CAF50` fill, semi-transparent background) |
| `android/.../res/drawable/notification_dot_green.xml` | Green circle (8dp) for flight path endpoints |
| `android/.../res/drawable/ic_flight_progress.xml` | Airplane vector icon (18dp, dark `#424242`, rotated 90° to point right) |
| `android/.../res/drawable/notification_progress_bar.xml` | Original green progress bar drawable (legacy, kept for reference) |
| `lib/services/flight_tracking_foreground_service.dart` | Dart-side service: phase logic, MethodChannel calls, FCM state updates |

### Notification Channels (Android)

| Channel ID | Name | Importance | Purpose |
|------------|------|------------|---------|
| `flight_tracking_service` | Flight Tracking Service | LOW | Foreground service keepalive (managed by `flutter_foreground_task`) |
| `flight_tracking_live` | Live Flight Tracking | LOW | Per-flight custom RemoteViews notifications |

### Collapsed View Design

```
┌────────────────────────────────────────────┐
│  Dubai  ●━━━━━━━━━━✈╌╌╌╌╌╌╌╌●  London    │
│  In Flight                                 │
│  Arriving 3:30 PM                          │
└────────────────────────────────────────────┘
```

- City names (bold, 15sp) on each side
- Green dots (7dp) as flight path endpoints
- `ProgressBar` with custom `notification_flight_path` drawable
- Airplane icon (`ic_flight_progress`) overlaid at the progress point via `FrameLayout` + dynamic `setViewPadding`
- Status text with color coding (green=on time, orange=delayed/diverted, red=cancelled)
- Subtitle text (time info stripped of redundant route prefix)

### Expanded View Design

```
┌────────────────────────────────────────────┐
│  EK500                      3:30 PM London │
│  Dubai  10:00 AM                           │
│  ●━━━━━━━━━━✈╌╌╌╌╌╌╌╌●                    │
│  In Flight                   2h 30m until  │
│  Departed 10:00 AM · ETA: 3:30 PM         │
└────────────────────────────────────────────┘
```

- Flight number header (left) + arrival time/city (right, bold)
- Origin city + departure time
- Flight path (same dots+progress+airplane pattern as collapsed)
- Status (left, color-coded) + time remaining (right, computed from chronometerWhen)
- Expanded detail text (gate, terminal, baggage info)

### Airplane Icon Positioning

The airplane icon is positioned dynamically at the progress percentage along the progress bar:

```kotlin
val dm = context.resources.displayMetrics
val density = dm.density
val screenWidthDp = dm.widthPixels / density
// Estimate progress bar width by subtracting system chrome + city text padding
val progressBarWidthPx = ((screenWidthDp - 210f) * density).toInt().coerceAtLeast(1) // collapsed
val iconHalfPx = (9 * density).toInt()  // half of 18dp icon
val paddingStartPx = ((progressBarWidthPx * progress / 100f) - iconHalfPx).toInt().coerceAtLeast(0)
collapsed.setViewPadding(R.id.flight_icon_container, paddingStartPx, 0, 0, 0)
```

### Phase Logic (Dart-side, in `_showFlightNotification`)

| Phase | Condition | Title | Progress | Chronometer |
|-------|-----------|-------|----------|-------------|
| **Pre-departure** | `!departed && status != cancelled/diverted` | `EK500 — On Time` or `EK500 — Delayed 15m` | 0% | Countdown to departure |
| **In Flight** | `departed && !landed` | `EK500 — In Flight` | `(elapsed / total) * 100` | Countdown to arrival |
| **Landed** | `landed` or `status == 'landed'` | `EK500 — Landed` | 100% | None |
| **Cancelled** | `status == 'cancelled'` | `EK500 — Cancelled` | 0% | None |
| **Diverted** | `status == 'diverted'` | `EK500 — Diverted` | 50% | None |

### Status Color Coding (Kotlin-side)

```kotlin
val statusColor = when {
    status.startsWith("Delayed") -> 0xFFFF9800.toInt()  // Orange
    status == "Cancelled" -> 0xFFF44336.toInt()          // Red
    status.startsWith("Diverted") -> 0xFFFF9800.toInt()  // Orange
    else -> 0xFF4CAF50.toInt()                            // Green
}
```

### FCM → Notification State Updates

When FCM messages arrive (via `_handleFcmMessage`), the tracked flight's mutable state is updated and the notification is re-rendered:

| FCM Event | State Change |
|-----------|-------------|
| `DELAY` / `DEPARTURE_DELAY` | `tracked.delayMinutes = ...` |
| `GATE_CHANGE` / `GATE_DEPARTURE` | `tracked.gate = ...` |
| `DEPARTURE` | `tracked.status = 'departed'` |
| `ARRIVAL` | `tracked.status = 'landed'` + schedule removal in 30min |
| `CANCELLATION` | `tracked.status = 'cancelled'` |
| `DIVERSION` | `tracked.status = 'diverted'` + `tracked.diversionAirport = ...` |
| `BAGGAGE` | `tracked.baggageBelt = ...` |

### Flight Tracking Eligibility

Flights are auto-tracked when:
- Already departed AND (no arrival time OR arrived < 30 min ago)
- Departing within the next 24 hours

Auto-removed:
- 30 minutes after landing (`_scheduleRemoval`)
- Foreground service stops when no flights remain

### Params Passed via MethodChannel

```dart
await _channel.invokeMethod('showFlightNotification', {
  'notificationId': tracked.notificationId,     // int (hash of Firestore ID)
  'title': title,                                // "EK500 — In Flight"
  'contentLine': contentLine,                    // "Dubai → London · Arriving 3:30 PM"
  'expandedText': expandedText,                  // "Departed 10:00 AM · ETA: 3:30 PM"
  'route': route,                                // "Dubai → London"
  'progress': progress,                          // 0-100
  'useChronometer': useChronometer,              // bool
  'chronometerWhen': chronometerWhen,            // epoch millis
  'countDown': countDown,                        // bool (always true)
  'originCity': tracked.originCity,              // "Dubai"
  'destinationCity': tracked.destinationCity,    // "London"
  'flightNumber': tracked.flightNumber,          // "EK500"
  'departureTime': _formatTime(...),             // "10:00 AM"
  'arrivalTime': _formatTime(...),               // "3:30 PM"
});
```

### RemoteViews Constraints (Important)

Android RemoteViews only supports a **limited set of views**:
- **Allowed:** `LinearLayout`, `RelativeLayout`, `FrameLayout`, `GridLayout`, `TextView`, `ImageView`, `ProgressBar`, `Button`, `Chronometer`, `ViewFlipper`
- **NOT allowed:** `View`, `ConstraintLayout`, `RecyclerView`, custom views, `CardView`
- Spacers must use `<TextView>` with `layout_weight` instead of `<View>`

---

## 14. AUTH FLOW

```
App Launch
  → Check Firebase Auth state
  → If no user: Create anonymous account
  → If user exists: Load AppUser from Firestore

Google Sign-In (when user taps sign in)
  → GoogleSignIn with scopes [email, profile, gmail.readonly]
  → Get Google auth credentials
  → If currently anonymous: Try to link anonymous → Google
    → If credential-already-in-use: Sign in with Google directly, migrate flights
  → Create/update user doc in Firestore
  → Store refresh token (for backend Gmail access)
  → Setup Gmail watch (for push notifications)
```

---

## 15. BUILD & DEPLOY

### Flutter
```bash
flutter pub get                    # Install dependencies
flutter analyze                    # Lint
flutter build ios                  # Build iOS
flutter build apk                 # Build Android
flutter build web                 # Build web
```

### Firebase Functions
```bash
cd functions
npm install                        # Install deps
npm run build                      # Compile TypeScript → lib/
npm run deploy                     # Deploy to Firebase (or: firebase deploy --only functions)
npm run serve                      # Local emulator
```

### Train Scraper (Cloud Run)
```bash
cd train-scraper
docker build -t train-scraper .
docker run -p 8080:8080 train-scraper

# Deploy to Cloud Run:
gcloud builds submit --tag gcr.io/airtime-4e65f/train-scraper
gcloud run deploy train-scraper --image gcr.io/airtime-4e65f/train-scraper --region us-central1
```

---

## 16. KNOWN ISSUES & NOTES

1. **Security:** API credentials are hardcoded in Dart code (`cirium_api_service.dart`) and in `ciriumAlertService.ts`. Should use env vars or Firebase Remote Config.
2. **Security:** `functions/.env` contains exposed secrets. Listed in `.gitignore` but may have been tracked.
3. **Single-file UI:** All UI is in `main.dart` (~1800+ lines). Consider splitting into separate screen files.
4. **No state management:** Uses raw `setState()`. May need Provider/Riverpod as app grows.
5. **Currently only flight bookings** are processed by the Gmail pipeline. Hotel/train/bus etc. are detected but skipped in `analyzeTravel`.
6. **Fixed currency rates:** INR conversion uses hardcoded rates (USD=83, EUR=90, GBP=105).
7. **Gmail Watch expiry:** Watch expires after some weeks. No automatic renewal mechanism.
8. **Default map location:** Cape Town (-33.8688, 18.7029) — should be user's location or first flight's origin.
9. **Train scraper** relies on web scraping which is fragile — sites can change their HTML structure.

---

## 17. PRD SUMMARY (from PRD_SCREEN_STATES.txt)

The full PRD defines **41+ distinct states** across two screens:

### Homepage (Flight List)
- 6 page-level states: Loading, Empty, Error, Offline, Gmail sync, Token expired
- Flight sections: Next Flight (hero card), Upcoming, Past
- 7 flight status states: S, A, L, C, D, R, U
- Gate/terminal states: TBA, announced, changed
- Delay tiers: On-time, Minor (1-15m), Moderate (16-60m), Significant (61+m), Early
- Data enrichment: In-progress, complete, partial failure, total failure, stale

### Flight Detail Page
- 3 page-level states: Loading, Not found, Refresh in progress
- Timing section: Scheduled, Delayed, Active, Landed, Cancelled
- Airport info: Departure/arrival with gate, terminal, weather
- Performance rating: Available, limited data, unavailable
- Aircraft equipment: Known, code-only, unknown, changed
- Live tracker: Available, limited, unavailable (active flights only)
- Context-specific action buttons per flight state
- Alert history/notification log

### Edge Cases Covered
- Booking vs Cirium data conflicts (prefer Cirium real-time data)
- Duplicate flight handling
- Flight number changes mid-trip
- Multi-segment: connecting, round-trip, multi-city
- Time-based transitions: to "next flight", to "past", check-in window opening

---

*Last updated: 2026-02-11*
*Auto-generated from full codebase analysis*
