# Firebase Functions Architecture for Airtime

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP                               │
├─────────────────────────────────────────────────────────────────┤
│  1. Google Sign-In (with Gmail scope)                           │
│     → Gets OAuth access token for Gmail API                     │
│                                                                  │
│  2. Call Firebase Function                                       │
│     → Pass access token + options (date range, batch, etc.)     │
│                                                                  │
│  3. Receive structured travel data                               │
│     → Display in UI                                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FIREBASE FUNCTIONS                            │
├─────────────────────────────────────────────────────────────────┤
│  analyzeTravel (HTTPS Callable Function)                        │
│                                                                  │
│  Input:                                                          │
│    - accessToken: string (Gmail OAuth token from Flutter)       │
│    - options: { batchSize, batch, dateFrom, dateTo }            │
│                                                                  │
│  Process:                                                        │
│    1. Use accessToken to call Gmail API                         │
│    2. Fetch emails matching travel query                        │
│    3. For each email:                                           │
│       a. Detect booking type (flight/hotel/train/etc)           │
│       b. Extract PDF attachments or email body                  │
│       c. Parse PDF to text                                      │
│       d. Send to OpenAI for structured extraction               │
│    4. Return structured travel data                             │
│                                                                  │
│  Output:                                                         │
│    - travels: Array of booking objects                          │
│    - moreBatches: boolean                                       │
│    - nextBatch: number | null                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL SERVICES                             │
├─────────────────────────────────────────────────────────────────┤
│  • Gmail API - Fetch user's travel emails                       │
│  • OpenAI API - Extract structured data from text               │
└─────────────────────────────────────────────────────────────────┘
```

## Why This Architecture?

1. **Security**: OpenAI API key stays in Firebase Functions, not in the app
2. **Reusability**: Same functions can be used by web/iOS/Android
3. **Scalability**: Firebase handles scaling automatically
4. **Simplicity**: Flutter only handles auth, backend does heavy lifting

## Project Structure

### Firebase Functions (`functions/`)

```
functions/
├── src/
│   ├── index.ts                    # Export all functions
│   ├── analyzeTravel.ts            # Main callable function
│   ├── services/
│   │   ├── gmailService.ts         # Gmail API wrapper
│   │   ├── pdfService.ts           # PDF text extraction
│   │   └── openaiService.ts        # OpenAI API wrapper
│   ├── utils/
│   │   ├── bookingDetector.ts      # Detect booking type from email
│   │   ├── emailQuery.ts           # Gmail search query builder
│   │   └── airlineData.ts          # Airline normalization data
│   └── types/
│       ├── schemas.ts              # OpenAI prompt schemas
│       └── bookingTypes.ts         # TypeScript interfaces
├── package.json
├── tsconfig.json
└── .env                            # OPENAI_API_KEY
```

### Flutter App Updates (`lib/`)

```
lib/
├── services/
│   ├── google_auth_service.dart    # Google Sign-In + Gmail scope
│   └── travel_service.dart         # Call Firebase Function
├── models/
│   └── travel/
│       ├── booking_types.dart      # All booking type models
│       ├── travel_response.dart    # API response model
│       └── amount.dart             # Common models
└── (existing files)
```

## Authentication Flow

```
┌──────────────┐    ┌─────────────────┐    ┌──────────────────┐
│ Flutter App  │───▶│ Google Sign-In  │───▶│ Google OAuth     │
└──────────────┘    └─────────────────┘    └──────────────────┘
                                                    │
                    ┌───────────────────────────────┘
                    ▼
        ┌─────────────────────────┐
        │ Access Token            │
        │ (includes gmail.readonly│
        │  scope)                 │
        └─────────────────────────┘
                    │
                    ▼
        ┌─────────────────────────┐
        │ Pass to Firebase        │
        │ Function                │
        └─────────────────────────┘
                    │
                    ▼
        ┌─────────────────────────┐
        │ Firebase Function uses  │
        │ token to call Gmail API │
        └─────────────────────────┘
```

## Required Setup

### 1. Firebase Project
- Create Firebase project (or use existing)
- Enable Cloud Functions
- Set up billing (required for external API calls)

### 2. Google Cloud Console
- Enable Gmail API
- Create OAuth 2.0 credentials
  - iOS: Bundle ID
  - Android: Package name + SHA-1/SHA-256

### 3. Environment Variables (Firebase)
```bash
firebase functions:config:set openai.key="sk-..."
```

### 4. Flutter Dependencies
```yaml
dependencies:
  firebase_core: ^3.8.1
  cloud_functions: ^5.1.4
  google_sign_in: ^6.2.1
```

## Data Flow Example

### Request
```dart
// Flutter
final result = await FirebaseFunctions.instance
    .httpsCallable('analyzeTravel')
    .call({
      'accessToken': googleSignIn.currentUser.authentication.accessToken,
      'options': {
        'batchSize': 5,
        'batch': 1,
      },
    });
```

### Response
```json
{
  "travels": [
    {
      "booking_type": "flight",
      "booking_reference": "ABC123",
      "flights": [
        {
          "flight_number": "LX147",
          "airline": "Swiss",
          "departure": {
            "city": "Delhi",
            "airport_code": "DEL",
            "datetime": "2025-01-15T01:45:00"
          },
          "arrival": {
            "city": "Zurich",
            "airport_code": "ZRH",
            "datetime": "2025-01-15T06:20:00"
          }
        }
      ],
      "passengers": [...],
      "total_amount_paid": { "amount": 45000, "currency": "INR" }
    }
  ],
  "moreBatches": true,
  "nextBatch": 2
}
```

## What I Need From You

1. **Firebase Project ID** (or should I create one?)
2. **OpenAI API Key** (reuse from seasonal or new?)
3. **Google Cloud Project** (reuse seasonal's OAuth or new?)

## Implementation Order

1. ✅ Plan architecture (this document)
2. Set up Firebase in Flutter project
3. Create Firebase Functions project
4. Port services (Gmail, PDF, OpenAI)
5. Port schemas and types
6. Create Flutter Google Sign-In
7. Create Flutter travel service
8. Test end-to-end
