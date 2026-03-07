/**
 * PII Redaction Utility
 *
 * Strips sensitive personally identifiable information from email content
 * BEFORE it is sent to any external AI API. Preserves email structure while
 * removing identifiers like Aadhaar numbers, PAN, credit card numbers,
 * bank account numbers, IFSC codes, phone numbers, email addresses, and CVVs.
 */

// ============================================
// Known bank/financial domains to preserve
// ============================================

const KNOWN_BANK_EMAIL_DOMAINS: Set<string> = new Set([
  // === PUBLIC SECTOR BANKS ===
  'sbi.co.in',
  'pnb.co.in',
  'bankofbaroda.co.in',
  'canarabank.in',
  'canarabank.com',
  'unionbankofindia.co.in',
  'bankofindia.co.in',
  'indianbank.in',
  'centralbankofindia.co.in',
  'iob.in',
  'ucobank.com',
  'bankofmaharashtra.in',
  'psbindia.com',
  // === PRIVATE SECTOR BANKS ===
  'hdfcbank.net',
  'hdfcbank.com',
  'icicibank.com',
  'axisbank.com',
  'kotak.com',
  'indusind.com',
  'yesbank.in',
  'idbi.co.in',
  'idbidirect.in',
  'idfcfirstbank.com',
  'federalbank.co.in',
  'bandhanbank.com',
  'rblbank.com',
  'southindianbank.com',
  'karnatakabank.com',
  'kvb.co.in',
  'cityunionbank.com',
  'tmb.in',
  'dfrbank.com',
  'dhanlaxmibank.com',
  'dcbbank.com',
  'csb.co.in',
  'jkbank.com',
  'nainitalbank.co.in',
  // === SMALL FINANCE BANKS ===
  'aubank.in',
  'equitasbank.com',
  'ujjivansfb.in',
  'janabank.com',
  'esafbank.com',
  'utkarshbank.com',
  'suryodaybank.com',
  'capitalbank.co.in',
  'nesfb.com',
  'shivalikbank.com',
  'unitybank.in',
  // === PAYMENT BANKS ===
  'airtelbank.com',
  'ippb.in',
  'finobank.com',
  'jiopaymentbank.com',
  // === FOREIGN BANKS ===
  'hsbc.co.in',
  'sc.com',
  'dbs.com',
  'db.com',
  'barclays.in',
  'bnpparibas.co.in',
  'citibank.co.in',
  'citi.com',
  // === CREDIT CARD ISSUERS ===
  'americanexpress.co.in',
  'sbicard.com',
  'bajajfinserv.in',
  'getonecard.com',
  'sliceit.com',
  'npci.org.in',
  // === UPI / PAYMENT / FINTECH ===
  'phonepe.com',
  'paytm.com',
  'cred.club',
  'amazonpay.in',
  'jupiter.money',
  'fi.money',
  'goniyo.com',
  'freo.money',
  'getsimpl.com',
  'lazypay.in',
  // === INVESTMENT ===
  'zerodha.com',
  'groww.in',
  'kuvera.in',
  'paytmmoney.com',
  'angelone.in',
  'upstox.com',
  'motilaloswal.com',
  'icicidirect.com',
  'hdfcsec.com',
  'smallcase.com',
]);

// ============================================
// Redaction Patterns (applied in order)
// ============================================

/**
 * 1. Aadhaar numbers: 12 digits, possibly separated by spaces or dashes
 *    e.g. "1234 5678 9012", "1234-5678-9012", "123456789012"
 */
const AADHAAR_PATTERN = /\b(\d{4}[\s-]?\d{4}[\s-]?\d{4})\b/g;

/**
 * Helper: Check if a 12-digit match is actually an Aadhaar number
 * (not a credit card partial, not preceded by currency symbols, etc.)
 */
function isLikelyAadhaar(match: string, fullText: string, offset: number): boolean {
  const digitsOnly = match.replace(/[\s-]/g, '');
  if (digitsOnly.length !== 12) return false;

  // Check that it's not part of a 16-digit credit card sequence
  // Look ahead for more digit groups
  const afterMatch = fullText.substring(offset + match.length, offset + match.length + 10);
  if (/^[\s-]?\d{4}/.test(afterMatch)) return false;

  // Check it's not preceded by currency indicators
  const beforeMatch = fullText.substring(Math.max(0, offset - 10), offset);
  if (/(?:Rs\.?|INR|₹)\s*$/i.test(beforeMatch)) return false;

  return true;
}

/**
 * 2. PAN numbers: 5 uppercase letters + 4 digits + 1 uppercase letter
 *    e.g. "ABCDE1234F"
 */
const PAN_PATTERN = /\b([A-Z]{5}[0-9]{4}[A-Z])\b/g;

/**
 * 3. Credit card numbers: 16 digits, possibly separated by spaces or dashes
 *    e.g. "1234 5678 9012 3456", "1234-5678-9012-3456"
 */
const CREDIT_CARD_PATTERN = /\b(\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4})\b/g;

/**
 * 4. Bank account numbers: 9-18 pure digit sequences
 *    Must NOT be preceded by currency symbols/words (Rs, INR, ₹)
 *    Must NOT match date patterns
 */
const ACCOUNT_NUMBER_PATTERN = /\b(\d{9,18})\b/g;

/**
 * 5. IFSC codes: 4 uppercase letters + 0 + 6 alphanumeric characters
 *    e.g. "HDFC0001234"
 */
const IFSC_PATTERN = /\b([A-Z]{4}0[A-Z0-9]{6})\b/g;

/**
 * 6. Indian phone numbers: 10 digits starting with 6-9, optionally prefixed with +91
 *    e.g. "+91 9876543210", "+919876543210", "9876543210"
 */
const PHONE_WITH_PREFIX_PATTERN = /\+91[\s-]?([6-9]\d{9})\b/g;
const PHONE_STANDALONE_PATTERN = /(?<!\d)([6-9]\d{9})(?!\d)/g;

/**
 * 7. Email addresses (standard pattern)
 */
const EMAIL_PATTERN = /\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b/g;

/**
 * 8. CVV/CVC: 3-4 digits preceded by CVV, CVC, or "security code"
 */
const CVV_PATTERN = /(?:CVV|CVC|security\s*code)\s*[:\s]?\s*(\d{3,4})\b/gi;


// ============================================
// Helper: Date pattern detection
// ============================================

/**
 * Checks if a digit sequence looks like a date.
 * Handles: DDMMYYYY, MMDDYYYY, YYYYMMDD, and similar 8-digit date patterns.
 */
function isDateLike(digits: string): boolean {
  if (digits.length === 8) {
    // DDMMYYYY
    const dd1 = parseInt(digits.substring(0, 2), 10);
    const mm1 = parseInt(digits.substring(2, 4), 10);
    const yyyy1 = parseInt(digits.substring(4, 8), 10);
    if (dd1 >= 1 && dd1 <= 31 && mm1 >= 1 && mm1 <= 12 && yyyy1 >= 1900 && yyyy1 <= 2100) {
      return true;
    }

    // YYYYMMDD
    const yyyy2 = parseInt(digits.substring(0, 4), 10);
    const mm2 = parseInt(digits.substring(4, 6), 10);
    const dd2 = parseInt(digits.substring(6, 8), 10);
    if (yyyy2 >= 1900 && yyyy2 <= 2100 && mm2 >= 1 && mm2 <= 12 && dd2 >= 1 && dd2 <= 31) {
      return true;
    }
  }

  return false;
}

/**
 * Checks if a digit sequence is preceded by a currency indicator,
 * meaning it's likely a monetary amount and not an account number.
 */
function isPrecededByCurrency(text: string, offset: number): boolean {
  const before = text.substring(Math.max(0, offset - 15), offset);
  // Match Rs, Rs., INR, ₹ possibly followed by spaces
  return /(?:Rs\.?|INR|₹|amount|balance|amt)\s*$/i.test(before);
}

/**
 * Checks if a digit sequence is preceded by a reference/UTR label
 */
function isPrecededByReference(text: string, offset: number): boolean {
  const before = text.substring(Math.max(0, offset - 25), offset);
  return /(?:ref\.?\s*(?:no\.?)?|UTR|reference|txn\s*(?:id|no)?|transaction\s*(?:id|no)?)\s*[:\s]?\s*$/i.test(before);
}

/**
 * Checks if the context around a digit sequence suggests it's a date
 * (e.g. preceded by "date", "on", or surrounded by date separators)
 */
function isInDateContext(text: string, offset: number, matchLength: number): boolean {
  const before = text.substring(Math.max(0, offset - 15), offset);
  // Preceded by "date" or "/" or "-" suggesting a formatted date
  if (/(?:date|dated|on|dt)\s*[:\s]?\s*$/i.test(before)) return true;
  // Check if it's part of a DD/MM/YYYY pattern
  if (/\d{1,2}[\/\-]\d{1,2}[\/\-]$/.test(before)) return true;
  const after = text.substring(offset + matchLength, offset + matchLength + 5);
  if (/^[\/\-]\d{1,2}[\/\-]?\d{0,4}/.test(after)) return true;
  return false;
}


// ============================================
// Main Redaction Function
// ============================================

/**
 * Redacts personally identifiable information from email content.
 *
 * This function should be called on raw email body text BEFORE sending
 * the content to any external AI service (e.g., Claude API).
 *
 * Redaction rules are applied in a specific order to avoid conflicts
 * (e.g., credit cards are redacted before account numbers so that
 * a 16-digit CC number isn't partially matched as an account number).
 */
export function redactPII(content: string): string {
  if (!content) return content;

  let result = content;

  // ---- 1. Aadhaar numbers (12 digits with optional spaces/dashes) ----
  // We need a custom replacement to avoid false positives
  result = redactAadhaar(result);

  // ---- 2. PAN numbers ----
  result = result.replace(PAN_PATTERN, '[REDACTED_PAN]');

  // ---- 3. Credit card numbers (16 digits with optional separators) ----
  result = result.replace(CREDIT_CARD_PATTERN, (_match, digits: string) => {
    const cleaned = digits.replace(/[\s-]/g, '');
    if (cleaned.length === 16) {
      const lastFour = cleaned.substring(12);
      return `Card ending ${lastFour}`;
    }
    return _match;
  });

  // ---- 4. Bank account numbers (9-18 digit sequences) ----
  result = redactAccountNumbers(result);

  // ---- 5. IFSC codes ----
  result = result.replace(IFSC_PATTERN, '[REDACTED_IFSC]');

  // ---- 6. Phone numbers ----
  result = redactPhoneNumbers(result);

  // ---- 7. Email addresses (except known bank domains) ----
  result = result.replace(EMAIL_PATTERN, (match) => {
    const atIndex = match.lastIndexOf('@');
    const domain = match.substring(atIndex + 1).toLowerCase();
    if (KNOWN_BANK_EMAIL_DOMAINS.has(domain)) {
      return match; // Preserve known bank email addresses
    }
    return '[REDACTED_EMAIL]';
  });

  // ---- 8. CVV/CVC ----
  result = result.replace(CVV_PATTERN, (match, cvvDigits: string) => {
    // Replace only the digits portion, keep the label
    return match.replace(cvvDigits, '[REDACTED_CVV]');
  });

  return result;
}


// ============================================
// Specialized Redaction Helpers
// ============================================

/**
 * Redacts Aadhaar numbers while avoiding false positives with
 * credit card numbers and amounts.
 */
function redactAadhaar(text: string): string {
  // Match 12-digit patterns (with optional space/dash separators)
  // but NOT 16-digit patterns (credit cards)
  let result = '';
  let lastIndex = 0;

  // Reset regex state
  AADHAAR_PATTERN.lastIndex = 0;

  let match: RegExpExecArray | null;
  while ((match = AADHAAR_PATTERN.exec(text)) !== null) {
    const fullMatch = match[0];
    const offset = match.index;
    const digits = fullMatch.replace(/[\s-]/g, '');

    // Only process 12-digit sequences
    if (digits.length === 12 && isLikelyAadhaar(fullMatch, text, offset)) {
      result += text.substring(lastIndex, offset);
      result += '[REDACTED_AADHAAR]';
      lastIndex = offset + fullMatch.length;
    }
  }

  result += text.substring(lastIndex);
  return result;
}

/**
 * Redacts bank account numbers (9-18 digit sequences) while
 * carefully avoiding amounts, dates, and reference numbers.
 */
function redactAccountNumbers(text: string): string {
  let result = '';
  let lastIndex = 0;

  ACCOUNT_NUMBER_PATTERN.lastIndex = 0;

  let match: RegExpExecArray | null;
  while ((match = ACCOUNT_NUMBER_PATTERN.exec(text)) !== null) {
    const fullMatch = match[0];
    const offset = match.index;
    const digits = fullMatch;

    // Skip if preceded by currency indicator (it's an amount)
    if (isPrecededByCurrency(text, offset)) continue;

    // Skip if it looks like a date
    if (isDateLike(digits)) continue;

    // Skip if in a date context
    if (isInDateContext(text, offset, fullMatch.length)) continue;

    // Skip if preceded by a reference/UTR label (preserve reference numbers)
    if (isPrecededByReference(text, offset)) continue;

    // Skip if already redacted (part of a previous replacement)
    const beforeText = text.substring(Math.max(0, offset - 30), offset);
    if (/REDACTED_/.test(beforeText) && /\]$/.test(beforeText.trim())) continue;

    // It's likely a bank account number — redact, keeping last 4 digits
    const lastFour = digits.substring(digits.length - 4);
    result += text.substring(lastIndex, offset);
    result += `A/c XX${lastFour}`;
    lastIndex = offset + fullMatch.length;
  }

  result += text.substring(lastIndex);
  return result;
}

/**
 * Redacts Indian phone numbers while being careful about
 * other numeric sequences.
 */
function redactPhoneNumbers(text: string): string {
  // Handle +91 prefixed numbers first
  PHONE_WITH_PREFIX_PATTERN.lastIndex = 0;
  let result = text.replace(
    PHONE_WITH_PREFIX_PATTERN,
    '[REDACTED_PHONE]'
  );

  // Handle standalone 10-digit numbers starting with 6-9
  // Must not be part of a longer number sequence
  PHONE_STANDALONE_PATTERN.lastIndex = 0;
  result = result.replace(
    PHONE_STANDALONE_PATTERN,
    (match, _digits, offset) => {
      const fullText = result;

      // Don't redact if preceded by currency (it's an amount)
      if (isPrecededByCurrency(fullText, offset)) return match;

      // Don't redact if preceded by reference labels
      if (isPrecededByReference(fullText, offset)) return match;

      // Don't redact if it's preceded by "A/c XX" (already redacted account)
      const before = fullText.substring(Math.max(0, offset - 10), offset);
      if (/A\/c\s*XX/.test(before)) return match;

      return '[REDACTED_PHONE]';
    }
  );

  return result;
}
