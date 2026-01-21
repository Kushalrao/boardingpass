"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.detectBookingType = detectBookingType;
// Booking type detection patterns
const BOOKING_TYPE_PATTERNS = {
    flight: {
        subjects: ['flight booking', 'flight confirmation', 'boarding pass', 'e-ticket', 'flight itinerary', 'airline ticket'],
        domains: ['spicejet.com', 'indigo.com', 'airindia.com', 'vistara.com', 'goair.in', 'airasia.com', 'airasia.in', 'akasaair.com', 'emirates.com', 'etihad.com', 'qatarairways.com', 'singaporeair.com', 'cathaypacific.com', 'lufthansa.com', 'britishairways.com', 'airfrance.com', 'klm.com', 'united.com', 'delta.com', 'americanairlines.com', 'southwest.com', 'jetblue.com', 'alaskaair.com', 'virginatlantic.com', 'qantas.com', 'japanairlines.com', 'ana.co.jp', 'turkishairlines.com', 'thaiairways.com', 'malaysiaairlines.com', 'airchina.com', 'china-eastern.com', 'china-southern.com'],
    },
    hotel: {
        subjects: ['hotel booking', 'hotel confirmation', 'hotel reservation', 'hotel itinerary', 'accommodation', 'check-in', 'check out', 'room booking', 'stay confirmed'],
        domains: ['booking.com', 'hotels.com', 'agoda.com', 'oyo.com', 'fabhotels.com', 'treebo.com', 'marriott.com', 'hilton.com', 'ihg.com', 'hyatt.com', 'accor.com', 'radissonhotels.com', 'tajhotels.com', 'oberoihotels.com', 'leela.com', 'lemontreehotels.com', 'gingerhotels.com'],
    },
    vacation_rental: {
        subjects: ['reservation confirmed', 'booking confirmed', 'trip confirmed'],
        domains: ['airbnb.com', 'vrbo.com', 'homeaway.com', 'sonder.com', 'onefinestay.com', 'plumguide.com', 'homestay.com'],
    },
    train: {
        subjects: ['train booking', 'train ticket', 'rail ticket', 'pnr'],
        domains: ['irctc.co.in', 'confirmtkt.com', 'railyatri.in', 'trainman.in', 'erail.in', 'trainline.com', 'raileurope.com', 'eurail.com', 'amtrak.com', 'sncf.com', 'deutschebahn.com'],
    },
    bus: {
        subjects: ['bus booking', 'bus ticket'],
        domains: ['redbus.in', 'abhibus.com', 'zopbus.com', 'flixbus.com', 'megabus.com', 'greyhound.com', 'nationalexpress.com'],
    },
    event: {
        subjects: ['event ticket', 'concert ticket', 'show ticket', 'sports ticket'],
        domains: [],
    },
    attraction: {
        subjects: ['attraction ticket', 'tour booking', 'activity booking', 'museum ticket'],
        domains: ['getyourguide.com', 'viator.com', 'klook.com', 'headout.com', 'musement.com'],
    },
    visa: {
        subjects: ['visa confirmation', 'visa appointment', 'visa approval', 'visa application'],
        domains: ['vfsglobal.com', 'cibtvisas.com', 'travisa.com', 'visahq.com', 'ivisa.com'],
    },
};
// Aggregator domains that can send multiple booking types
const AGGREGATOR_DOMAINS = [
    'makemytrip.com', 'ixigo.com', 'goibibo.com', 'scapia.com', 'cleartrip.com',
    'easemytrip.com', 'yatra.com', 'paytm.com', 'expedia.com', 'expedia.co.in',
    'priceline.com', 'orbitz.com', 'travelocity.com', 'hotwire.com', 'trip.com',
    'tripadvisor.com', 'tripadvisor.in'
];
function detectBookingType(subject, fromEmail) {
    const subjectLower = subject.toLowerCase();
    const fromLower = fromEmail.toLowerCase();
    const isAggregator = AGGREGATOR_DOMAINS.some(domain => fromLower.includes(domain));
    if (isAggregator) {
        // For aggregators, check subject keywords first (more reliable)
        // Check in specific order - hotel before flight to avoid "itinerary" matching flight
        if (BOOKING_TYPE_PATTERNS.hotel.subjects.some(keyword => subjectLower.includes(keyword))) {
            return 'hotel';
        }
        if (BOOKING_TYPE_PATTERNS.train.subjects.some(keyword => subjectLower.includes(keyword))) {
            return 'train';
        }
        if (BOOKING_TYPE_PATTERNS.bus.subjects.some(keyword => subjectLower.includes(keyword))) {
            return 'bus';
        }
        if (BOOKING_TYPE_PATTERNS.visa.subjects.some(keyword => subjectLower.includes(keyword))) {
            return 'visa';
        }
        if (BOOKING_TYPE_PATTERNS.attraction.subjects.some(keyword => subjectLower.includes(keyword))) {
            return 'attraction';
        }
        if (BOOKING_TYPE_PATTERNS.event.subjects.some(keyword => subjectLower.includes(keyword))) {
            return 'event';
        }
        if (BOOKING_TYPE_PATTERNS.vacation_rental.subjects.some(keyword => subjectLower.includes(keyword))) {
            return 'vacation_rental';
        }
        if (BOOKING_TYPE_PATTERNS.flight.subjects.some(keyword => subjectLower.includes(keyword))) {
            return 'flight';
        }
    }
    // Check domains for direct providers
    for (const [type, patterns] of Object.entries(BOOKING_TYPE_PATTERNS)) {
        if (patterns.domains.some(domain => fromLower.includes(domain))) {
            return type;
        }
    }
    // Check subject keywords
    for (const [type, patterns] of Object.entries(BOOKING_TYPE_PATTERNS)) {
        if (patterns.subjects.some(keyword => subjectLower.includes(keyword))) {
            return type;
        }
    }
    // Fallback inference from common patterns
    if (subjectLower.includes('hotel') || subjectLower.includes('check-in') || subjectLower.includes('room') || subjectLower.includes('stay')) {
        return 'hotel';
    }
    if (subjectLower.includes('train') || subjectLower.includes('rail') || subjectLower.includes('pnr')) {
        return 'train';
    }
    if (subjectLower.includes('bus')) {
        return 'bus';
    }
    if (subjectLower.includes('visa')) {
        return 'visa';
    }
    if (subjectLower.includes('attraction') || subjectLower.includes('tour') || subjectLower.includes('activity')) {
        return 'attraction';
    }
    if (subjectLower.includes('event') || subjectLower.includes('concert')) {
        return 'event';
    }
    if (subjectLower.includes('airbnb') || subjectLower.includes('vacation rental') || subjectLower.includes('apartment')) {
        return 'vacation_rental';
    }
    if (subjectLower.includes('flight') || subjectLower.includes('boarding') || subjectLower.includes('e-ticket') || subjectLower.includes('airline')) {
        return 'flight';
    }
    // Default to flight for travel-related emails
    return 'flight';
}
//# sourceMappingURL=bookingDetector.js.map