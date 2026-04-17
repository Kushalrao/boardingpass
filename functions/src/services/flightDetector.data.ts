// ============================================
// Flight Detector Data
// Sender domains, subject patterns, body keywords
// ============================================

export interface SubjectPattern {
  name: string;
  regex: RegExp;
  weight: number;
  flightSpecific: boolean;
}

export interface BodyKeyword {
  phrase: string;
  weight: number;
  flightSpecific: boolean;
}

export interface AntiPattern {
  name: string;
  regex: RegExp;
  penalty: number;
}

// ============================================
// SENDER DOMAINS
// ============================================

/**
 * Airline sender domains.
 * An email from one of these is very likely flight-related (score +4).
 */
export const AIRLINE_DOMAINS: Set<string> = new Set([
  // --- Indian Airlines ---
  'goindigo.in',                   // IndiGo
  'airindia.com',                  // Air India
  'airindia.in',                   // Air India (alternate)
  'spicejet.com',                  // SpiceJet
  'airvistara.com',                // Vistara (merged into Air India, legacy emails)
  'airasia.com',                   // AirAsia India
  'akasaair.com',                  // Akasa Air
  'allianceair.in',                // Alliance Air
  'starair.in',                    // Star Air
  'flybigair.com',                 // FlyBig

  // --- Middle East ---
  'emirates.com',                  // Emirates
  'qatarairways.com',              // Qatar Airways
  'qatarairways.com.qa',           // Qatar Airways (alternate)
  'etihad.com',                    // Etihad
  'etihadairways.com',             // Etihad (alternate)
  'flydubai.com',                  // Flydubai
  'omanair.com',                   // Oman Air
  'saudia.com',                    // Saudia
  'gulfair.com',                   // Gulf Air

  // --- Southeast Asia ---
  'singaporeair.com',              // Singapore Airlines
  'malaysiaairlines.com',          // Malaysia Airlines
  'thaiairways.com',               // Thai Airways
  'cathaypacific.com',             // Cathay Pacific
  'srilankan.com',                 // SriLankan Airlines
  'vietnamairlines.com',           // Vietnam Airlines
  'garuda-indonesia.com',          // Garuda Indonesia
  'bangkokair.com',                // Bangkok Airways
  'cebupacificair.com',            // Cebu Pacific
  'scootair.com',                  // Scoot

  // --- Europe ---
  'lufthansa.com',                 // Lufthansa
  'email.ba.com',                  // British Airways
  'britishairways.com',            // British Airways (alternate)
  'klm.com',                       // KLM
  'airfrance.com',                 // Air France
  'thy.com',                       // Turkish Airlines
  'turkishairlines.com',           // Turkish Airlines (alternate)
  'ryanair.com',                   // Ryanair
  'easyjet.com',                   // EasyJet
  'swiss.com',                     // Swiss International
  'austrian.com',                  // Austrian Airlines
  'brusselsairlines.com',          // Brussels Airlines
  'iberia.com',                    // Iberia
  'vueling.com',                   // Vueling
  'finnair.com',                   // Finnair
  'norwegianair.com',              // Norwegian
  'norwegian.com',                 // Norwegian (alternate)
  'lot.com',                       // LOT Polish Airlines
  'aeroflot.com',                  // Aeroflot
  'aegeanair.com',                 // Aegean Airlines
  'wizzair.com',                   // Wizz Air

  // --- North America ---
  'united.com',                    // United Airlines
  'delta.com',                     // Delta Air Lines
  'aa.com',                        // American Airlines
  'americanairlines.com',          // American Airlines (alternate)
  'southwest.com',                 // Southwest Airlines
  'southwestairlines.com',         // Southwest (alternate)
  'jetblue.com',                   // JetBlue
  'aircanada.com',                 // Air Canada
  'alaskaair.com',                 // Alaska Airlines
  'spirit.com',                    // Spirit Airlines
  'frontierairlines.com',          // Frontier Airlines
  'hawaiianairlines.com',          // Hawaiian Airlines

  // --- East Asia ---
  'jal.com',                       // Japan Airlines
  'ana.co.jp',                     // ANA
  'koreanair.com',                 // Korean Air
  'asiana.com',                    // Asiana Airlines
  'airchina.com',                  // Air China
  'csair.com',                     // China Southern
  'ceair.com',                     // China Eastern
  'evaair.com',                    // EVA Air
  'tigerair.com',                  // Tigerair

  // --- Africa / Oceania ---
  'ethiopianairlines.com',         // Ethiopian Airlines
  'flyegypt.com',                  // FlyEgypt
  'egyptair.com',                  // EgyptAir
  'flysaa.com',                    // South African Airways
  'qantas.com',                    // Qantas
  'airnewzealand.com',             // Air New Zealand
]);

/**
 * OTA (Online Travel Agency) sender domains.
 * These send flight, hotel, cab, train bookings — need flight-specific signal to confirm (score +2).
 */
export const OTA_DOMAINS: Set<string> = new Set([
  // --- Indian OTAs ---
  'makemytrip.com',                // MakeMyTrip
  'goibibo.com',                   // Goibibo
  'cleartrip.com',                 // Cleartrip
  'easemytrip.com',                // EaseMyTrip
  'easemytrip.in',                 // EaseMyTrip (alternate)
  'yatra.com',                     // Yatra
  'ixigo.com',                     // ixigo
  'via.com',                       // Via.com
  'paytm.com',                     // Paytm Travel
  'paytm.in',                      // Paytm (alternate)
  'flipkart.com',                  // Flipkart Travel
  'happyeasygo.com',               // HappyEasyGo
  'abhibus.com',                   // AbhiBus (also does flights)
  'confirmtkt.com',                // ConfirmTkt
  'railyatri.in',                  // RailYatri (also does flights)
  'thrillophilia.com',             // Thrillophilia
  'thomascook.in',                 // Thomas Cook India
  'sotc.in',                       // SOTC Travel
  'akbartravels.com',              // Akbar Travels
  'musafir.com',                   // Musafir
  'travelguru.com',                // TravelGuru
  'goomo.com',                     // Goomo
  'travalour.com',                 // Travalour
  'flightraj.com',                 // FlightRaj
  'adanione.com',                  // Adani One (flights)
  'udchalo.com',                   // UdChalo (defence/flights)
  'dpauls.com',                    // DPauls Travel
  'flybig.in',                     // FlyBig OTA
  'myflightsearch.com',            // MyFlightSearch
  'policybazaar.com',              // PolicyBazaar (also does flights via PB Partners)
  'amazon.in',                     // Amazon Flight Bookings
  'phonepe.com',                   // PhonePe Travel
  'tatacliq.com',                  // Tata Cliq (via Cleartrip integration)

  // --- International OTAs ---
  'expedia.com',                   // Expedia
  'booking.com',                   // Booking.com
  'kayak.com',                     // Kayak
  'skyscanner.com',                // Skyscanner
  'skyscanner.net',                // Skyscanner (alternate)
  // Note: google.com excluded — too broad, matches all Google emails.
  'trip.com',                      // Trip.com
  'kiwi.com',                      // Kiwi.com
  'traveloka.com',                 // Traveloka
  'agoda.com',                     // Agoda (also does flights)
  'cheapflights.com',              // Cheapflights
  'momondo.com',                   // Momondo
  'orbitz.com',                    // Orbitz
  'travelocity.com',               // Travelocity
  'priceline.com',                 // Priceline
  'hopper.com',                    // Hopper
  'flightaware.com',               // FlightAware (tracking, not booking — but useful)
]);

// ============================================
// SUBJECT PATTERNS
// ============================================

/**
 * Subject line regex patterns with weights.
 * flightSpecific: true means this pattern is unique to flights.
 * flightSpecific: false means hotels/trains/cars could also match.
 */
export const SUBJECT_PATTERNS: SubjectPattern[] = [
  // --- Flight-specific (weight 3) ---
  { name: 'e-ticket',              regex: /\b(e-?ticket|eticket)\b/i,                              weight: 3, flightSpecific: true },
  { name: 'flight-confirmation',   regex: /\bflight\s+(confirmation|booking|itinerary|reservation)\b/i, weight: 3, flightSpecific: true },
  { name: 'pnr-code',             regex: /\bPNR\s*[:\-]?\s*[A-Z]{6}\b/i,                          weight: 3, flightSpecific: true },
  { name: 'flight-number',        regex: /\bflight\s+#?\d/i,                                       weight: 3, flightSpecific: true },
  { name: 'boarding-pass',        regex: /\bboarding\s+pass/i,                                     weight: 3, flightSpecific: true },
  { name: 'itinerary-confirm',    regex: /\bitinerary\s+(confirmation|receipt)\b/i,                 weight: 3, flightSpecific: true },
  { name: 'flight-booked',        regex: /\bflight\s+(booked|reserved)\b/i,                         weight: 3, flightSpecific: true },
  { name: 'airline-ticket',       regex: /\b(airline\s+ticket|air\s+ticket)\b/i,                    weight: 3, flightSpecific: true },
  { name: 'checkin-reminder',     regex: /\b(check-?in|web\s*check-?in)\s*(reminder|open|now)\b/i,  weight: 2, flightSpecific: true },

  // --- Generic booking (weight 2) — could be hotel/car/train ---
  { name: 'booking-confirmed',    regex: /\bbooking\s+(confirmed|confirmation|reference)\b/i,       weight: 2, flightSpecific: false },
  { name: 'reservation-confirmed', regex: /\breservation\s+(confirmed|confirmation)\b/i,            weight: 2, flightSpecific: false },
  { name: 'trip-confirmation',    regex: /\btrip\s+confirmation\b/i,                                weight: 2, flightSpecific: false },
  { name: 'travel-itinerary',     regex: /\btravel\s+itinerary\b/i,                                weight: 2, flightSpecific: false },
  { name: 'ticket-confirmed',     regex: /\bticket\s+(confirmation|confirmed|booked)\b/i,           weight: 2, flightSpecific: false },
  { name: 'booking-success',      regex: /\bbooking\s+(success|successful)\b/i,                     weight: 2, flightSpecific: false },

  // --- Generic signals (weight 1) ---
  { name: 'confirmation',         regex: /\bconfirmation\b/i,                                       weight: 1, flightSpecific: false },
  { name: 'itinerary',            regex: /\bitinerary\b/i,                                          weight: 1, flightSpecific: false },
  { name: 'booking-id',           regex: /\bbooking\s+(id|ref|number)\b/i,                          weight: 1, flightSpecific: false },
];

// ============================================
// SUBJECT ANTI-PATTERNS
// ============================================

/**
 * Subject anti-patterns.
 * When any of these fire, body scoring is skipped entirely —
 * if the subject already tells us it's not a flight, body noise shouldn't rescue it.
 */
export const ANTI_PATTERNS: AntiPattern[] = [
  // --- Accommodation (catches hotel bookings from OTAs) ---
  { name: 'accommodation-name',    regex: /\b(hotel|inn|resort|cottages?|hostels?|villas?|motels?|lodges?|apartments?|residences?|suites?\b(?!\s*class))/i, penalty: 3 },
  { name: 'voucher',               regex: /\bvoucher\b/i,                                          penalty: 3 },

  // --- Non-flight transport ---
  { name: 'non-flight-transport',  regex: /\b(cab|car|bus|train|rail)\s+(booking|reservation|confirmation)\b/i, penalty: 3 },

  // --- Marketing / promotional ---
  { name: 'flight-deal',           regex: /\bflight\s+(deal|offer|sale|discount)\b/i,              penalty: 4 },
  { name: 'price-alert',           regex: /\b(price\s+alert|fare\s+alert|price\s+drop)\b/i,        penalty: 4 },
  { name: 'newsletter',            regex: /\b(newsletter|unsubscribe|weekly\s+digest)\b/i,          penalty: 4 },
  { name: 'promotional',           regex: /\b(flat\s+\d+%\s+off|coupon|promo\s+code|cashback\s+offer)\b/i, penalty: 4 },
  { name: 'save-offer',            regex: /\b(save\s+up\s+to|%\s*off|ending\s+soon)\b/i,           penalty: 4 },
  { name: 'holiday-package',       regex: /\b(holiday\s+package|tour\s+package|vacation\s+package)\b/i, penalty: 3 },

  // --- Gamification ---
  { name: 'reward-gamification',   regex: /\b(reward\s+(unlocked|earned)|unlock(ed)?.*reward)\b/i,  penalty: 4 },
];

// ============================================
// BODY KEYWORDS
// ============================================

/**
 * Keywords checked against the plain-text body.
 * flightSpecific: true = only flights use this term.
 * flightSpecific: false = hotels/trains could also match.
 */
export const BODY_KEYWORDS: BodyKeyword[] = [
  // --- Flight-specific (weight 2) ---
  { phrase: 'boarding pass',        weight: 2, flightSpecific: true },
  { phrase: 'e-ticket',             weight: 2, flightSpecific: true },
  { phrase: 'eticket',              weight: 2, flightSpecific: true },
  { phrase: 'flight number',        weight: 2, flightSpecific: true },
  { phrase: 'departure terminal',   weight: 2, flightSpecific: true },
  { phrase: 'arrival terminal',     weight: 2, flightSpecific: true },
  { phrase: 'airline pnr',          weight: 2, flightSpecific: true },
  { phrase: 'booking pnr',          weight: 2, flightSpecific: true },
  { phrase: 'departure time',       weight: 2, flightSpecific: true },
  { phrase: 'arrival time',         weight: 2, flightSpecific: true },
  { phrase: 'gate no',              weight: 2, flightSpecific: true },
  { phrase: 'baggage allowance',    weight: 2, flightSpecific: true },
  { phrase: 'seat number',          weight: 2, flightSpecific: true },
  { phrase: 'flight details',       weight: 2, flightSpecific: true },
  { phrase: 'web check-in',         weight: 2, flightSpecific: true },

  // --- Generic (weight 1-2) — hotels/trains also use these ---
  { phrase: 'check-in',             weight: 2, flightSpecific: false },
  { phrase: 'passenger name',       weight: 1, flightSpecific: false },
  { phrase: 'travel date',          weight: 1, flightSpecific: false },
  { phrase: 'journey details',      weight: 1, flightSpecific: false },
  { phrase: 'trip details',         weight: 1, flightSpecific: false },
  { phrase: 'booking reference',    weight: 1, flightSpecific: false },
  { phrase: 'confirmation number',  weight: 1, flightSpecific: false },
  { phrase: 'travel insurance',     weight: 1, flightSpecific: false },
];

/**
 * Airport route pattern — matches "DEL -> BOM", "BLR to HYD", "CCU-MAA", "DEL→BOM", etc.
 * Weight: 2, flightSpecific: true
 */
export const AIRPORT_ROUTE_REGEX = /\b[A-Z]{3}\s*(?:[-\u2192\u2794>]+|to)\s*[A-Z]{3}\b/;
