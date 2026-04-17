import {
  AIRLINE_DOMAINS,
  OTA_DOMAINS,
  SUBJECT_PATTERNS,
  ANTI_PATTERNS,
  BODY_KEYWORDS,
  AIRPORT_ROUTE_REGEX,
} from './flightDetector.data';
import { EmailMessage } from './gmailService';

// ============================================
// Types
// ============================================

export interface DetectionResult {
  isFlightEmail: boolean;
  confidence: 'high' | 'medium' | 'low';
  score: number;
  matchedSignals: string[];
  senderCategory: 'airline' | 'ota' | 'unknown';
  senderDomain: string;
}

// ============================================
// Domain extraction
// ============================================

/**
 * Extracts the domain from a From header.
 * "IndiGo <noreply@goindigo.in>" => "goindigo.in"
 * "noreply@goindigo.in" => "goindigo.in"
 */
export function extractDomain(fromHeader: string): string {
  const angleMatch = fromHeader.match(/<([^>]+)>/);
  const email = angleMatch
    ? angleMatch[1]
    : fromHeader.trim();

  const atIndex = email.lastIndexOf('@');
  if (atIndex === -1) return '';
  return email.substring(atIndex + 1).toLowerCase();
}

/**
 * Checks if a sender domain (which may be a subdomain like notifications.goindigo.in)
 * matches any domain in the provided set.
 * Tries the full domain first, then progressively strips subdomains.
 */
function matchesDomainSet(domain: string, domainSet: Set<string>): boolean {
  if (!domain) return false;
  if (domainSet.has(domain)) return true;

  const parts = domain.split('.');
  for (let i = 1; i < parts.length - 1; i++) {
    const parent = parts.slice(i).join('.');
    if (domainSet.has(parent)) return true;
  }

  return false;
}

// ============================================
// Detection
// ============================================

/**
 * Scores an email to determine if it's a flight booking confirmation.
 *
 * Algorithm (5 steps):
 *
 *   1. Sender domain    → establishes context, not conviction
 *   2. Subject patterns  → score + track if flight-specific
 *   3. Subject anti-patterns → subtract. If any fires, body is SKIPPED.
 *   4. Body keywords     → only if no subject anti-pattern fired
 *   5. Minimum signal check:
 *        - OTA sender: must have at least one flight-specific signal
 *        - Airline sender: must have at least one non-sender signal
 *        - Unknown sender: must have at least one non-sender signal
 *
 * This prevents:
 *   - Hotel bookings from OTAs (generic signals, no flight-specific)
 *   - Marketing emails from airlines (domain alone, no content signal)
 *   - Train bookings rescued by body noise (anti-pattern blocks body)
 */
export function detectFlightEmail(email: EmailMessage): DetectionResult {
  let score = 0;
  const matchedSignals: string[] = [];
  let hasFlightSpecificSignal = false;
  let hasNonSenderSignal = false;
  let subjectAntiPatternFired = false;

  // --- Step 1: Sender domain ---
  const senderDomain = extractDomain(email.from);
  let senderCategory: 'airline' | 'ota' | 'unknown' = 'unknown';

  if (matchesDomainSet(senderDomain, AIRLINE_DOMAINS)) {
    senderCategory = 'airline';
    score += 4;
    matchedSignals.push(`airline_sender:${senderDomain}`);
  } else if (matchesDomainSet(senderDomain, OTA_DOMAINS)) {
    senderCategory = 'ota';
    score += 2;
    matchedSignals.push(`ota_sender:${senderDomain}`);
  }

  // --- Step 2: Subject patterns ---
  for (const pattern of SUBJECT_PATTERNS) {
    if (pattern.regex.test(email.subject)) {
      score += pattern.weight;
      matchedSignals.push(`subject:${pattern.name}`);
      hasNonSenderSignal = true;
      if (pattern.flightSpecific) hasFlightSpecificSignal = true;
    }
  }

  // --- Step 3: Subject anti-patterns ---
  // Only apply when sender is known (unknown senders already need high scores).
  // When an anti-pattern fires, body scoring is blocked — the subject is
  // more reliable than body noise for rejection.
  if (senderCategory !== 'unknown') {
    for (const anti of ANTI_PATTERNS) {
      if (anti.regex.test(email.subject)) {
        score -= anti.penalty;
        matchedSignals.push(`anti:${anti.name}`);
        subjectAntiPatternFired = true;
      }
    }
  }

  // --- Step 4: Body keywords (only if subject anti-pattern didn't fire) ---
  // If the subject already says "train booking" or "hotel voucher",
  // body keywords like "travel date" or "check-in" must not rescue it.
  if (!subjectAntiPatternFired && email.body && email.body.length > 20) {
    const bodyLower = email.body.toLowerCase();

    for (const keyword of BODY_KEYWORDS) {
      if (bodyLower.includes(keyword.phrase)) {
        score += keyword.weight;
        matchedSignals.push(`body:${keyword.phrase}`);
        hasNonSenderSignal = true;
        if (keyword.flightSpecific) hasFlightSpecificSignal = true;
      }
    }

    // Airport route pattern (e.g., DEL -> BOM)
    if (AIRPORT_ROUTE_REGEX.test(email.body)) {
      score += 2;
      matchedSignals.push('body:airport_route_pattern');
      hasNonSenderSignal = true;
      hasFlightSpecificSignal = true;
    }
  }

  // --- Step 5: Minimum signal check + thresholds ---
  // Sender domain establishes context but is never sufficient alone.
  //   - OTA: could be hotel/car/train. Require a flight-specific signal.
  //   - Airline: almost always flight-related, but could be marketing.
  //     Require any non-sender signal (subject or body match).
  //   - Unknown: require any non-sender signal.
  const meetsMinimumSignal = senderCategory === 'ota'
    ? hasFlightSpecificSignal
    : hasNonSenderSignal;

  let confidence: 'high' | 'medium' | 'low';
  let isFlightEmail: boolean;

  if (!meetsMinimumSignal) {
    isFlightEmail = false;
    confidence = 'low';
  } else if (score >= 6) {
    isFlightEmail = true;
    confidence = 'high';
  } else if (score >= 4) {
    isFlightEmail = true;
    confidence = 'medium';
  } else if (score >= 3 && senderCategory !== 'unknown') {
    isFlightEmail = true;
    confidence = 'low';
  } else {
    isFlightEmail = false;
    confidence = 'low';
  }

  return {
    isFlightEmail,
    confidence,
    score,
    matchedSignals,
    senderCategory,
    senderDomain,
  };
}
