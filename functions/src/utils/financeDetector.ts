import { FinanceEmailType } from '../types/financeTypes';

// ============================================
// Known Financial Sender Domains
// ============================================

const BANK_DOMAINS: Set<string> = new Set([
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
  // === FOREIGN BANKS IN INDIA ===
  'hsbc.co.in',
  'sc.com',
  'dbs.com',
  'db.com',
  'barclays.in',
  'bnpparibas.co.in',
  'citibank.co.in',
  'citi.com',
]);

const UPI_DOMAINS: Set<string> = new Set([
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
]);

const CC_ISSUER_DOMAINS: Set<string> = new Set([
  'americanexpress.co.in',
  'sbicard.com',
  'bajajfinserv.in',
  'getonecard.com',
  'sliceit.com',
  'npci.org.in',
]);

const INVESTMENT_DOMAINS: Set<string> = new Set([
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

/** All known financial domains combined */
const ALL_FINANCIAL_DOMAINS: Set<string> = new Set([
  ...BANK_DOMAINS,
  ...UPI_DOMAINS,
  ...CC_ISSUER_DOMAINS,
  ...INVESTMENT_DOMAINS,
]);

// ============================================
// Keyword Patterns
// ============================================

const OTP_AUTH_PATTERNS: RegExp = /\b(OTP|one\s*time\s*password|verification\s*code|secure\s*code|login\s*alert|password\s*reset|2FA)\b/i;

const STATEMENT_PATTERNS: RegExp = /\b(e-?statement|account\s*statement|statement)\b/i;
const CC_IN_SUBJECT_PATTERNS: RegExp = /\b(credit\s*card|card\s*statement)\b/i;

const SALARY_PATTERNS: RegExp = /\b(salary|payroll)\b|credited.*salary|salary.*credited/i;

const EMI_PATTERNS: RegExp = /\b(EMI|equated\s*monthly|loan)\b/i;

const REFUND_PATTERNS: RegExp = /\b(refund|reversal|cashback\s*credited)\b/i;

const INVESTMENT_PATTERNS: RegExp = /\b(SIP|mutual\s*fund|units\s*allotted|NAV|dividend)\b/i;

const UPI_PATTERNS: RegExp = /\b(UPI|unified\s*payment)\b/i;

const CC_TRANSACTION_PATTERNS: RegExp = /\b(card|credit\s*card)\b.*\b(debited|used|spent|charged)\b|\b(debited|used|spent|charged)\b.*\b(card|credit\s*card)\b/i;

const GENERAL_TRANSACTION_PATTERNS: RegExp = /\b(debited|credited|transaction|transferred|received|withdrawn)\b/i;

// ============================================
// Helper: Extract domain from "From" header
// ============================================

/**
 * Extracts the domain from an email "From" header.
 * Handles formats like:
 *   - "HDFC Bank <alerts@hdfcbank.net>"
 *   - "alerts@hdfcbank.net"
 *   - "<alerts@hdfcbank.net>"
 */
function extractDomain(from: string): string {
  // Try to extract email from angle brackets first
  const bracketMatch = from.match(/<([^>]+)>/);
  const email = bracketMatch ? bracketMatch[1] : from.trim();

  const atIndex = email.lastIndexOf('@');
  if (atIndex === -1) return '';

  return email.substring(atIndex + 1).toLowerCase().trim();
}

/**
 * Checks if the sender email is specifically noreply@google.com
 */
function isGooglePaySender(from: string): boolean {
  const bracketMatch = from.match(/<([^>]+)>/);
  const email = bracketMatch ? bracketMatch[1] : from.trim();
  return email.toLowerCase() === 'noreply@google.com';
}

// ============================================
// Subject-based classification for known domains
// ============================================

function classifyBySubject(subject: string, domain: string): FinanceEmailType {
  const sub = subject; // keep original for regex matching (patterns are case-insensitive)

  // Statement detection
  if (STATEMENT_PATTERNS.test(sub)) {
    // Determine if it's a credit card statement or bank statement
    if (CC_IN_SUBJECT_PATTERNS.test(sub) || CC_ISSUER_DOMAINS.has(domain)) {
      return 'cc_statement';
    }
    return 'bank_statement';
  }

  // Salary
  if (SALARY_PATTERNS.test(sub)) {
    return 'salary_credit';
  }

  // EMI
  if (EMI_PATTERNS.test(sub)) {
    return 'emi_debit';
  }

  // Refund
  if (REFUND_PATTERNS.test(sub)) {
    return 'refund';
  }

  // Investment
  if (INVESTMENT_PATTERNS.test(sub) || INVESTMENT_DOMAINS.has(domain)) {
    return 'investment';
  }

  // UPI
  if (UPI_PATTERNS.test(sub)) {
    return 'upi_alert';
  }

  // Credit card transaction (card + debited/used/spent/charged)
  if (CC_TRANSACTION_PATTERNS.test(sub)) {
    return 'cc_alert';
  }

  // General transaction keywords
  if (GENERAL_TRANSACTION_PATTERNS.test(sub)) {
    return 'transaction_alert';
  }

  // From a known financial domain but subject didn't match any specific pattern
  // Still likely financial — classify as transaction_alert for bank/UPI domains
  if (UPI_DOMAINS.has(domain)) {
    return 'upi_alert';
  }

  return 'unknown';
}

// ============================================
// Main Detection Function
// ============================================

/**
 * Detects the type of financial email based on the subject line and sender.
 *
 * Classification priority:
 *  1. OTP/Auth filter (always first)
 *  2. Known financial domain + subject keyword matching
 *  3. Google Pay special case
 *  4. Default: 'unknown'
 */
export function detectFinanceEmailType(subject: string, from: string): FinanceEmailType {
  // Normalize inputs
  const sub = subject || '';
  const sender = from || '';

  // ---- Step 1: OTP / Auth filter (always first) ----
  if (OTP_AUTH_PATTERNS.test(sub)) {
    return 'otp_or_auth';
  }

  // ---- Step 2 & 3: Check sender domain against known financial domains ----
  const domain = extractDomain(sender);

  if (ALL_FINANCIAL_DOMAINS.has(domain)) {
    return classifyBySubject(sub, domain);
  }

  // ---- Step 4: Google Pay special case ----
  if (isGooglePaySender(sender)) {
    if (/\b(UPI|payment|Google\s*Pay|GPay)\b/i.test(sub)) {
      return 'upi_alert';
    }
    // Google sends many non-financial emails; don't classify those
    return 'unknown';
  }

  // ---- Step 5: Subject keyword fallback for unknown domains ----
  // If the email has financial keywords in the subject, classify it
  // regardless of sender domain. Claude extraction will skip non-financial ones.
  if (
    GENERAL_TRANSACTION_PATTERNS.test(sub) ||
    STATEMENT_PATTERNS.test(sub) ||
    SALARY_PATTERNS.test(sub) ||
    EMI_PATTERNS.test(sub) ||
    REFUND_PATTERNS.test(sub) ||
    CC_TRANSACTION_PATTERNS.test(sub) ||
    UPI_PATTERNS.test(sub) ||
    INVESTMENT_PATTERNS.test(sub)
  ) {
    return classifyBySubject(sub, domain);
  }

  // ---- Step 6: Default ----
  return 'unknown';
}

/**
 * Returns true if the email is a financial email worth processing.
 * Excludes OTP/auth emails and unknown/unrecognized emails.
 */
export function isFinancialEmail(subject: string, from: string): boolean {
  const type = detectFinanceEmailType(subject, from);
  return type !== 'unknown' && type !== 'otp_or_auth';
}
