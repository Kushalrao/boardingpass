"use strict";
// ============================================
// Flight Grouper
// Extracts identifiers from detected flight emails
// and groups them into unique flights using union-find.
// ============================================
Object.defineProperty(exports, "__esModule", { value: true });
exports.extractIdentifiers = extractIdentifiers;
exports.groupFlightEmails = groupFlightEmails;
// ============================================
// Identifier Extraction
// ============================================
const MONTH_MAP = {
    jan: '01', feb: '02', mar: '03', apr: '04', may: '05', jun: '06',
    jul: '07', aug: '08', sep: '09', oct: '10', nov: '11', dec: '12',
};
// PNR patterns — 6-char alphanumeric, starts with a letter
const PNR_PATTERNS = [
    /\bPNR\s*[/:\-.]?\s*([A-Z][A-Z0-9]{5})\b/g,
    /\bItinerary\s*[-:]\s*([A-Z][A-Z0-9]{5})\b/g,
    /\bBooking\s+Ref\.?\s*:?\s*([A-Z][A-Z0-9]{5})\b/g,
];
// Booking ID patterns — longer alphanumeric codes from OTAs
const BOOKING_ID_PATTERNS = [
    /\bBooking\s+ID\s*[:.]\s*([A-Z0-9]{10,})/gi,
    /\b(IF\d{14,})/g, // ixigo
    /\b(NF[A-Z0-9]{15,})/g, // MakeMyTrip
    /\b(GOFLDNT[A-Z0-9]+)/g, // Goibibo
];
// Trip ID pattern
const TRIP_ID_PATTERN = /\bTrip\s+ID\s+(\d{8,})/gi;
// Flight number pattern — airline code + number
const FLIGHT_NUM_PATTERN = /\b(AI|6E|SG|UK|I5|G8|QP|EK|QR|SQ|BA|LH|TK|EY|FZ|WY|GF|9W)\s*[-]?\s*(\d{2,4})\b/g;
// Date pattern — "21 Oct 2025", "01 Jan 2026", "28Dec25", etc.
const DATE_PATTERNS = [
    /\b(\d{1,2})\s*(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*[',]?\s*(\d{2,4})\b/gi,
    /\b(\d{1,2})(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)(\d{2,4})\b/gi,
];
// Route pattern — airport codes "DEL -> BOM", "From DEL To BLR"
const ROUTE_PATTERNS = [
    /\b([A-Z]{3})\s*(?:[-\u2192\u2794>]+|to)\s*([A-Z]{3})\b/g,
    /\bFrom\s+([A-Z]{3})\s+To\s+([A-Z]{3})\b/gi,
];
// Airline detection from sender domain
const AIRLINE_NAMES = {
    'goindigo.in': 'IndiGo',
    'airindia.com': 'Air India',
    'airindia.in': 'Air India',
    'spicejet.com': 'SpiceJet',
    'airvistara.com': 'Vistara',
    'airasia.com': 'AirAsia',
    'akasaair.com': 'Akasa Air',
    'emirates.com': 'Emirates',
    'qatarairways.com': 'Qatar Airways',
    'singaporeair.com': 'Singapore Airlines',
    'lufthansa.com': 'Lufthansa',
    'britishairways.com': 'British Airways',
};
const AIRLINE_CODES = {
    'AI': 'Air India', '6E': 'IndiGo', 'SG': 'SpiceJet',
    'UK': 'Vistara', 'I5': 'AirAsia India', 'G8': 'Go First',
    'QP': 'Akasa Air', 'EK': 'Emirates', 'QR': 'Qatar Airways',
    'SQ': 'Singapore Airlines', 'BA': 'British Airways', 'LH': 'Lufthansa',
    'TK': 'Turkish Airlines', 'EY': 'Etihad', 'FZ': 'Flydubai',
    'WY': 'Oman Air', 'GF': 'Gulf Air',
};
function extractSenderDomain(from) {
    const m = from.match(/<([^>]+)>/) || from.match(/([^\s]+@[^\s]+)/);
    if (!m)
        return '';
    const email = m[1] || m[0];
    const at = email.lastIndexOf('@');
    if (at === -1)
        return '';
    const domain = email.substring(at + 1).toLowerCase();
    // Strip subdomains
    const parts = domain.split('.');
    for (let i = 0; i < parts.length - 1; i++) {
        const candidate = parts.slice(i).join('.');
        if (AIRLINE_NAMES[candidate])
            return candidate;
    }
    return domain;
}
function parseDate(day, month, year) {
    const m = MONTH_MAP[month.toLowerCase()];
    if (!m)
        return null;
    let y = year;
    if (y.length === 2)
        y = parseInt(y) > 50 ? '19' + y : '20' + y;
    const d = day.padStart(2, '0');
    return `${y}-${m}-${d}`;
}
function matchAll(text, regex) {
    const results = [];
    // Reset lastIndex for global regexes
    const r = new RegExp(regex.source, regex.flags);
    let match;
    while ((match = r.exec(text)) !== null) {
        results.push(match);
    }
    return results;
}
function dedupe(arr) {
    return [...new Set(arr)];
}
function extractIdentifiers(email) {
    const text = `${email.subject}\n${email.body}`;
    // PNRs
    const pnrs = [];
    for (const pattern of PNR_PATTERNS) {
        for (const m of matchAll(text, pattern)) {
            pnrs.push(m[1].toUpperCase());
        }
    }
    // Booking IDs
    const bookingIds = [];
    for (const pattern of BOOKING_ID_PATTERNS) {
        for (const m of matchAll(text, pattern)) {
            const id = m[1] || m[0];
            bookingIds.push(id);
        }
    }
    // Trip IDs
    const tripIds = [];
    for (const m of matchAll(text, TRIP_ID_PATTERN)) {
        tripIds.push(m[1]);
    }
    // Flight numbers
    const flightNumbers = [];
    for (const m of matchAll(text, FLIGHT_NUM_PATTERN)) {
        flightNumbers.push(`${m[1]}-${m[2]}`);
    }
    // Dates
    const dates = [];
    for (const pattern of DATE_PATTERNS) {
        for (const m of matchAll(text, pattern)) {
            const d = parseDate(m[1], m[2], m[3]);
            if (d)
                dates.push(d);
        }
    }
    // Flight number + date composite keys
    const flightDateKeys = [];
    if (flightNumbers.length > 0 && dates.length > 0) {
        // Pair each flight number with each date found
        // In practice, most emails mention one flight and one date
        for (const fn of dedupe(flightNumbers)) {
            for (const dt of dedupe(dates)) {
                flightDateKeys.push(`${fn}:${dt}`);
            }
        }
    }
    // Routes
    const routes = [];
    for (const pattern of ROUTE_PATTERNS) {
        for (const m of matchAll(text, pattern)) {
            routes.push(`${m[1].toUpperCase()}-${m[2].toUpperCase()}`);
        }
    }
    // Airline
    let airline = null;
    const domain = extractSenderDomain(email.from);
    if (AIRLINE_NAMES[domain]) {
        airline = AIRLINE_NAMES[domain];
    }
    else {
        // Try to detect from flight number
        for (const fn of flightNumbers) {
            const code = fn.split('-')[0];
            if (AIRLINE_CODES[code]) {
                airline = AIRLINE_CODES[code];
                break;
            }
        }
    }
    return {
        pnrs: dedupe(pnrs),
        bookingIds: dedupe(bookingIds),
        tripIds: dedupe(tripIds),
        flightDateKeys: dedupe(flightDateKeys),
        flightNumbers: dedupe(flightNumbers),
        routes: dedupe(routes),
        dates: dedupe(dates),
        airline,
    };
}
// ============================================
// Union-Find
// ============================================
class UnionFind {
    constructor() {
        this.parent = new Map();
    }
    find(x) {
        if (!this.parent.has(x)) {
            this.parent.set(x, x);
        }
        let root = x;
        while (this.parent.get(root) !== root) {
            root = this.parent.get(root);
        }
        // Path compression
        let curr = x;
        while (curr !== root) {
            const next = this.parent.get(curr);
            this.parent.set(curr, root);
            curr = next;
        }
        return root;
    }
    union(a, b) {
        const rootA = this.find(a);
        const rootB = this.find(b);
        if (rootA !== rootB) {
            this.parent.set(rootB, rootA);
        }
    }
}
// ============================================
// Grouping
// ============================================
function groupFlightEmails(emails) {
    const uf = new UnionFind();
    const emailIdentifiers = new Map();
    const emailToKeys = new Map();
    // Step 1: Extract identifiers for each email
    for (const email of emails) {
        const ids = extractIdentifiers(email);
        emailIdentifiers.set(email.gmailMessageId, ids);
        // Collect all identifier keys for this email
        const keys = [];
        for (const p of ids.pnrs)
            keys.push(`PNR:${p}`);
        for (const b of ids.bookingIds)
            keys.push(`BID:${b}`);
        for (const t of ids.tripIds)
            keys.push(`TID:${t}`);
        for (const f of ids.flightDateKeys)
            keys.push(`FDK:${f}`);
        emailToKeys.set(email.gmailMessageId, keys);
    }
    // Step 2: Union all keys from the same email
    for (const [_emailId, keys] of emailToKeys) {
        for (let i = 1; i < keys.length; i++) {
            uf.union(keys[0], keys[i]);
        }
    }
    // Step 3: Group emails by their root key
    const groupMap = new Map();
    const orphans = [];
    for (const email of emails) {
        const keys = emailToKeys.get(email.gmailMessageId);
        if (keys.length === 0) {
            orphans.push(email);
            continue;
        }
        const root = uf.find(keys[0]);
        if (!groupMap.has(root)) {
            groupMap.set(root, []);
        }
        groupMap.get(root).push(email);
    }
    // Step 4: Build FlightRecord for each group
    const flights = [];
    let flightId = 1;
    for (const [_root, groupEmails] of groupMap) {
        // Merge all identifiers from all emails in the group
        const allPnrs = new Set();
        const allBookingIds = new Set();
        const allTripIds = new Set();
        const allFlightNumbers = new Set();
        const allRoutes = new Set();
        const allDates = new Set();
        let airline = null;
        for (const email of groupEmails) {
            const ids = emailIdentifiers.get(email.gmailMessageId);
            ids.pnrs.forEach(p => allPnrs.add(p));
            ids.bookingIds.forEach(b => allBookingIds.add(b));
            ids.tripIds.forEach(t => allTripIds.add(t));
            ids.flightNumbers.forEach(f => allFlightNumbers.add(f));
            ids.routes.forEach(r => allRoutes.add(r));
            ids.dates.forEach(d => allDates.add(d));
            if (ids.airline && !airline)
                airline = ids.airline;
        }
        // Pick best route (first one found)
        let route = null;
        const routeArr = [...allRoutes];
        if (routeArr.length > 0) {
            const [from, to] = routeArr[0].split('-');
            route = { from, to };
        }
        // Pick flight date (most common, or earliest)
        const sortedDates = [...allDates].sort();
        const flightDate = sortedDates.length > 0 ? sortedDates[0] : null;
        // Sort emails by date
        const sortedEmails = groupEmails.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
        flights.push({
            id: flightId++,
            pnrs: [...allPnrs],
            bookingIds: [...allBookingIds],
            tripIds: [...allTripIds],
            flightNumbers: [...allFlightNumbers],
            route,
            flightDate,
            airline,
            emailIds: sortedEmails.map(e => e.gmailMessageId),
            emailCount: sortedEmails.length,
            emailSubjects: sortedEmails.map(e => e.subject),
            firstEmailDate: sortedEmails[0]?.date || '',
            lastEmailDate: sortedEmails[sortedEmails.length - 1]?.date || '',
        });
    }
    // Sort flights by date (newest first)
    flights.sort((a, b) => {
        const da = a.flightDate || a.firstEmailDate;
        const db = b.flightDate || b.firstEmailDate;
        return db.localeCompare(da);
    });
    return { flights, orphans };
}
//# sourceMappingURL=flightGrouper.js.map