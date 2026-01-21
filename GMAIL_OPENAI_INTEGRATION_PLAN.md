# Gmail + OpenAI Integration Plan for Airtime

## Overview

Integrate functionality from the `seasonal` repo that:
1. Authenticates user with Google (Gmail access)
2. Fetches travel-related emails from Gmail
3. Parses email content and PDF attachments
4. Uses OpenAI to extract structured booking data

---

## What the Seasonal Repo Does

### Authentication Flow
- Google OAuth 2.0 with scope: `https://www.googleapis.com/auth/gmail.readonly`
- Stores access token and refresh token
- JWT-based session management

### Email Fetching
- Queries Gmail for travel-related emails using:
  - Subject keywords: "flight booking", "hotel confirmation", "boarding pass", etc.
  - Sender domains: makemytrip.com, booking.com, airlines, hotels, etc.
- Processes emails in batches (pagination support)
- Filters by date (currently hardcoded to 2025)

### Data Extraction
- Extracts text from PDF attachments (e-tickets, confirmations)
- Falls back to email body if no PDF
- Sends content to OpenAI GPT-3.5-turbo
- Returns structured JSON based on booking type schemas

### Supported Booking Types
1. **Flight** - Airlines, airports, passengers, baggage, fare breakdown
2. **Hotel** - Property, check-in/out, room details, amenities
3. **Train** - PNR, stations, coach/berth, passengers
4. **Bus** - Operator, boarding/dropping points, seats
5. **Event** - Venue, seats, tickets
6. **Attraction** - Tour/activity details, visit time
7. **Visa** - Application details, appointment
8. **Vacation Rental** - Airbnb-style properties

---

## Implementation Plan for Flutter

### Architecture Decision

**Recommended: Hybrid Approach**

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│  Backend API    │────▶│   Gmail API     │
│                 │     │  (Dart/Node)    │     │   OpenAI API    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Why Hybrid?**
- OpenAI API key should NOT be in client app (security)
- PDF parsing libraries are more mature on server-side
- Backend can handle token refresh seamlessly
- Rate limiting and caching can be managed server-side

**Alternative: Direct Flutter (Simpler, Less Secure)**
- Call APIs directly from Flutter
- Store API keys in app (NOT recommended for production)
- Use for prototyping only

---

## Phase 1: Google Sign-In & Gmail Access

### Dependencies to Add
```yaml
dependencies:
  google_sign_in: ^6.2.1
  googleapis: ^13.2.0
  googleapis_auth: ^1.6.0
```

### Implementation Steps
1. Create Google Cloud Project (if not exists)
2. Enable Gmail API in Google Cloud Console
3. Configure OAuth consent screen
4. Create OAuth 2.0 credentials for:
   - iOS (Bundle ID)
   - Android (Package name + SHA-1)
5. Implement `GoogleSignIn` with Gmail scope
6. Store tokens securely (flutter_secure_storage)

### Files to Create
- `lib/services/google_auth_service.dart` - Authentication logic
- `lib/services/gmail_service.dart` - Gmail API wrapper

---

## Phase 2: Email Fetching & Filtering

### Implementation Steps
1. Port the Gmail query from seasonal repo
2. Implement email list fetching with pagination
3. Implement email detail fetching (headers, body, attachments)
4. Add date filtering logic

### Files to Create
- `lib/models/email_models.dart` - Email data structures
- Update `gmail_service.dart` with fetch methods

---

## Phase 3: Content Extraction

### Option A: Backend Service (Recommended)
Create a simple backend that:
- Receives email content/PDF data
- Parses PDFs using pdf-parse or similar
- Calls OpenAI API
- Returns structured data

### Option B: Flutter-Only (Prototype)
- Use `syncfusion_flutter_pdf` or `pdf_text` for PDF parsing
- Call OpenAI API directly (requires API key in app)

### Files to Create
- `lib/services/openai_service.dart` - OpenAI API wrapper
- `lib/services/pdf_parser_service.dart` - PDF text extraction

---

## Phase 4: Data Models & Storage

### Port from Seasonal Repo
- All booking type models (Flight, Hotel, Train, etc.)
- Common models (Amount, Passenger, Location, etc.)
- Response wrapper models

### Files to Create
- `lib/models/travel/booking_types.dart` - All booking models
- `lib/models/travel/common.dart` - Shared models
- `lib/models/travel/travel_response.dart` - API response models

---

## Phase 5: Integration Service

### Main Service
Orchestrates the entire flow:
1. Authenticate user
2. Fetch emails
3. Extract content
4. Parse with OpenAI
5. Return structured data

### Files to Create
- `lib/services/travel_analyzer_service.dart` - Main orchestrator

---

## Required Credentials

### From You (User)
1. **Google Cloud Project**
   - OAuth 2.0 Client ID for iOS
   - OAuth 2.0 Client ID for Android
   - (Or I can guide you to create these)

2. **OpenAI API Key**
   - For GPT-3.5-turbo access
   - Current key from seasonal repo can be reused

### Configuration Files to Update
- `ios/Runner/Info.plist` - Google Sign-In URL schemes
- `android/app/build.gradle` - (if needed)
- `lib/config/api_keys.dart` - Store keys (gitignored)

---

## Questions Before Implementation

1. **Backend or Flutter-only?**
   - Backend: More secure, better PDF parsing
   - Flutter-only: Faster to implement, prototype quality

2. **Use existing Google Cloud project from seasonal?**
   - Yes: Reuse credentials
   - No: Create new project for airtime

3. **OpenAI model preference?**
   - GPT-3.5-turbo (faster, cheaper) - current
   - GPT-4 (more accurate, slower, expensive)

4. **Date filtering?**
   - Current year only?
   - Custom date range?
   - All time?

---

## Estimated File Structure After Implementation

```
lib/
├── config/
│   └── api_keys.dart          # API keys (gitignored)
├── models/
│   ├── travel/
│   │   ├── booking_types.dart # Flight, Hotel, Train, etc.
│   │   ├── common.dart        # Amount, Passenger, etc.
│   │   └── travel_response.dart
│   └── email_models.dart
├── services/
│   ├── google_auth_service.dart
│   ├── gmail_service.dart
│   ├── openai_service.dart
│   ├── pdf_parser_service.dart
│   └── travel_analyzer_service.dart
└── main.dart
```

---

## Next Steps

Once you approve this plan and answer the questions above, I will:
1. Add required dependencies
2. Set up Google Sign-In
3. Implement Gmail service
4. Port data models from seasonal
5. Implement OpenAI integration
6. Create the main travel analyzer service
