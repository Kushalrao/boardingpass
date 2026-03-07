// ============================================
// Statement PDF Password Patterns
// ============================================

export interface PasswordCandidate {
  password: string;
  source: string; // description of the pattern used
}

/**
 * Generate candidate passwords for a bank's PDF statement.
 *
 * Indian banks use widely varying password formats for their PDF statements.
 * This function generates all plausible candidates based on:
 *   - Date of birth (DOB)
 *   - Customer name (as on bank records / card)
 *   - Masked card/account number (last 4 digits from previous transactions)
 *
 * @param senderDomain     - Email sender domain (e.g., "hdfcbank.net")
 * @param dob              - Customer date of birth as a Date object
 * @param userName         - Customer full name
 * @param maskedNumber     - Last 4 digits of card or account (e.g., "5692")
 */
export function generatePasswordCandidates(
  _provider: string,
  senderDomain: string,
  dob: Date,
  userName?: string,
  maskedNumber?: string,
): PasswordCandidate[] {
  // Format DOB components
  const dd = dob.getDate().toString().padStart(2, '0');
  const mm = (dob.getMonth() + 1).toString().padStart(2, '0');
  const yyyy = dob.getFullYear().toString();
  const yy = yyyy.slice(2);
  const monthNames = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  const mmm = monthNames[dob.getMonth()];

  // Name components (first name, removing spaces)
  const nameClean = (userName || '').replace(/\s+/g, '');
  const name4Upper = nameClean.substring(0, 4).toUpperCase();
  const name4Lower = nameClean.substring(0, 4).toLowerCase();
  const name3Upper = nameClean.substring(0, 3).toUpperCase();
  const last4 = maskedNumber || '';

  const candidates: PasswordCandidate[] = [];
  const seen = new Set<string>();

  function add(password: string, source: string) {
    if (!password || password.length < 4 || seen.has(password)) return;
    seen.add(password);
    candidates.push({ password, source });
  }

  // Check if we have bank-specific patterns for this domain
  const bankPatterns = BANK_SPECIFIC_PATTERNS[senderDomain];

  if (bankPatterns) {
    // Generate bank-specific patterns first (highest priority)
    for (const pattern of bankPatterns) {
      switch (pattern) {
        // DOB-only formats
        case 'DDMMYYYY': add(`${dd}${mm}${yyyy}`, 'DOB DDMMYYYY'); break;
        case 'DDMMYY': add(`${dd}${mm}${yy}`, 'DOB DDMMYY'); break;
        case 'DDMM': add(`${dd}${mm}`, 'DOB DDMM'); break;
        case 'MMDD': add(`${mm}${dd}`, 'DOB MMDD'); break;

        // NAME (uppercase) + DOB combinations
        case 'NAME4_UPPER+DDMM':
          if (name4Upper) add(`${name4Upper}${dd}${mm}`, 'NAME4(UPPER)+DDMM');
          break;
        case 'NAME4_UPPER+DDMMYY':
          if (name4Upper) add(`${name4Upper}${dd}${mm}${yy}`, 'NAME4(UPPER)+DDMMYY');
          break;
        case 'NAME4_UPPER+DDMMYYYY':
          if (name4Upper) add(`${name4Upper}${dd}${mm}${yyyy}`, 'NAME4(UPPER)+DDMMYYYY');
          break;
        case 'NAME4_UPPER+YYYY':
          if (name4Upper) add(`${name4Upper}${yyyy}`, 'NAME4(UPPER)+YYYY');
          break;

        // NAME (lowercase) + DOB combinations
        case 'NAME4_LOWER+DDMM':
          if (name4Lower) add(`${name4Lower}${dd}${mm}`, 'name4(lower)+DDMM');
          break;
        case 'NAME4_LOWER+DDMMYY':
          if (name4Lower) add(`${name4Lower}${dd}${mm}${yy}`, 'name4(lower)+DDMMYY');
          break;
        case 'NAME4_LOWER+DDMMYYYY':
          if (name4Lower) add(`${name4Lower}${dd}${mm}${yyyy}`, 'name4(lower)+DDMMYYYY');
          break;

        // NAME + last 4 digits of card/account
        case 'NAME4_UPPER+LAST4':
          if (name4Upper && last4) add(`${name4Upper}${last4}`, 'NAME4(UPPER)+last4card');
          break;
        case 'NAME4_LOWER+LAST4':
          if (name4Lower && last4) add(`${name4Lower}${last4}`, 'name4(lower)+last4acct');
          break;

        // NAME3 + DOB
        case 'DDMM+NAME3_UPPER':
          if (name3Upper) add(`${dd}${mm}${name3Upper}`, 'DDMM+NAME3(UPPER)');
          break;

        // NAME + DDMMM (3-letter month) — Citibank style
        case 'NAME4_UPPER+DDMMM':
          if (name4Upper) add(`${name4Upper}${dd}${mmm}`, 'NAME4(UPPER)+DDMMM');
          break;
        case 'NAME4_LOWER+DDMMM':
          if (name4Lower) add(`${name4Lower}${dd}${mmm.toLowerCase()}`, 'name4(lower)+DDmmm');
          break;

        // DOB + last N digits of card
        case 'DDMMYYYY+LAST4':
          if (last4) add(`${dd}${mm}${yyyy}${last4}`, 'DDMMYYYY+last4card');
          break;
        case 'DDMMYY+LAST4':
          if (last4) add(`${dd}${mm}${yy}${last4}`, 'DDMMYY+last4card');
          break;

        default: break;
      }
    }
  }

  // ---- Always add common fallback patterns ----

  // DOB variants (most common across all banks)
  add(`${dd}${mm}${yyyy}`, 'DOB DDMMYYYY');
  add(`${dd}${mm}${yy}`, 'DOB DDMMYY');
  add(`${dd}${mm}`, 'DOB DDMM');
  add(`${mm}${dd}`, 'DOB MMDD');
  add(`${yyyy}${mm}${dd}`, 'DOB YYYYMMDD');
  add(`${mm}${dd}${yyyy}`, 'DOB MMDDYYYY');

  // NAME4 + DDMM (most common Indian bank pattern — both cases)
  if (name4Upper) {
    add(`${name4Upper}${dd}${mm}`, 'NAME4(UPPER)+DDMM');
    add(`${name4Lower}${dd}${mm}`, 'name4(lower)+DDMM');
  }

  // NAME4 + DDMMYY
  if (name4Upper) {
    add(`${name4Upper}${dd}${mm}${yy}`, 'NAME4(UPPER)+DDMMYY');
    add(`${name4Lower}${dd}${mm}${yy}`, 'name4(lower)+DDMMYY');
  }

  // NAME4 + DDMMYYYY
  if (name4Upper) {
    add(`${name4Upper}${dd}${mm}${yyyy}`, 'NAME4(UPPER)+DDMMYYYY');
    add(`${name4Lower}${dd}${mm}${yyyy}`, 'name4(lower)+DDMMYYYY');
  }

  // NAME4 + last 4 digits of card/account (HDFC CC style)
  if (name4Upper && last4) {
    add(`${name4Upper}${last4}`, 'NAME4(UPPER)+last4');
    add(`${name4Lower}${last4}`, 'name4(lower)+last4');
  }

  // NAME4 + YYYY (HDFC account alt)
  if (name4Upper) {
    add(`${name4Upper}${yyyy}`, 'NAME4(UPPER)+YYYY');
  }

  // DOB + last4 card (SBI Card style)
  if (last4) {
    add(`${dd}${mm}${yyyy}${last4}`, 'DDMMYYYY+last4');
    add(`${dd}${mm}${yy}${last4}`, 'DDMMYY+last4');
  }

  // NAME4 + DDMMM 3-letter month (Citibank style)
  if (name4Upper) {
    add(`${name4Upper}${dd}${mmm}`, 'NAME4(UPPER)+DDMMM');
    add(`${name4Lower}${dd}${mmm.toLowerCase()}`, 'name4(lower)+DDmmm');
  }

  // DDMM + NAME3 (Equitas style)
  if (name3Upper) {
    add(`${dd}${mm}${name3Upper}`, 'DDMM+NAME3');
  }

  // DD-MM-YYYY / DD/MM/YYYY (some older systems)
  add(`${dd}-${mm}-${yyyy}`, 'DOB DD-MM-YYYY');
  add(`${dd}/${mm}/${yyyy}`, 'DOB DD/MM/YYYY');

  return candidates;
}

// ============================================
// Bank-specific password pattern mapping
// ============================================

/**
 * Maps sender domains to an ordered list of password pattern tokens.
 * Patterns listed first are tried first (highest priority).
 *
 * Pattern tokens:
 *   DOB: DDMMYYYY, DDMMYY, DDMM, MMDD, YYYYMMDD
 *   NAME+DOB: NAME4_UPPER+DDMM, NAME4_LOWER+DDMM, NAME4_UPPER+DDMMYY, etc.
 *   NAME+CARD: NAME4_UPPER+LAST4, NAME4_LOWER+LAST4
 *   DOB+CARD: DDMMYYYY+LAST4, DDMMYY+LAST4
 *   SPECIAL: NAME4_UPPER+DDMMM (3-letter month), DDMM+NAME3_UPPER
 */
const BANK_SPECIFIC_PATTERNS: Record<string, string[]> = {
  // === PUBLIC SECTOR BANKS ===

  // SBI — account: last 5 mobile + DDMMYY (can't generate), CC: DDMMYYYY + last4
  'sbi.co.in': ['DDMMYYYY', 'DDMMYYYY+LAST4', 'DDMMYY'],

  // PNB — account: account number (can't generate), CC: name4(lower) + DDMMYYYY
  'pnb.co.in': ['NAME4_LOWER+DDMMYYYY', 'NAME4_UPPER+DDMMYYYY', 'DDMMYYYY'],

  // Bank of Baroda — name4(lower) + DDMM, or CRN
  'bankofbaroda.co.in': ['NAME4_LOWER+DDMM', 'NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // Canara Bank — CC: NAME4(UPPER) + MMDD (note: month-day order!)
  'canarabank.in': ['NAME4_UPPER+DDMM', 'DDMMYYYY'],
  'canarabank.com': ['NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // Union Bank — NAME4(UPPER) + DDMM
  'unionbankofindia.co.in': ['NAME4_UPPER+DDMM', 'NAME4_UPPER+LAST4', 'DDMMYYYY'],

  // Bank of India — name4(lower) + DDMM or account number
  'bankofindia.co.in': ['NAME4_LOWER+DDMM', 'NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // Indian Bank — account number (can't generate)
  'indianbank.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Central Bank — CIF + @ + DDMMYYYY (can't generate CIF)
  'centralbankofindia.co.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // IOB — first 4 CIF + last 4 mobile (can't generate)
  'iob.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // UCO Bank — mobile number (can't generate)
  'ucobank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Bank of Maharashtra — name4(lower) + DDMM
  'bankofmaharashtra.in': ['NAME4_LOWER+DDMM', 'NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // Punjab & Sind Bank
  'psbindia.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // === PRIVATE SECTOR BANKS ===

  // HDFC — account: CIF or NAME4(UPPER)+YYYY, CC: NAME4(UPPER)+last4 or NAME4(UPPER)+DDMM
  'hdfcbank.net': ['NAME4_UPPER+LAST4', 'NAME4_UPPER+DDMM', 'NAME4_UPPER+YYYY', 'DDMMYYYY'],
  'hdfcbank.com': ['NAME4_UPPER+LAST4', 'NAME4_UPPER+DDMM', 'NAME4_UPPER+YYYY', 'DDMMYYYY'],

  // ICICI — CC: name4(LOWER)+DDMM (case-sensitive!), account: NAME4(UPPER)+DDMM
  'icicibank.com': ['NAME4_LOWER+DDMM', 'NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // Axis — NAME4(UPPER)+DDMM or NAME4(UPPER)+last4
  'axisbank.com': ['NAME4_UPPER+DDMM', 'NAME4_UPPER+LAST4', 'DDMMYYYY'],

  // Kotak — account: CRN (can't generate), CC: name4(lower)+DDMM
  'kotak.com': ['NAME4_LOWER+DDMM', 'NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // IndusInd — NAME4(UPPER)+DDMM
  'indusind.com': ['NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // Yes Bank — CIF+DDMMYYYY (can't generate CIF)
  'yesbank.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // IDBI — CC: NAME4(UPPER)+DDMM, account: CIF
  'idbi.co.in': ['NAME4_UPPER+DDMM', 'DDMMYYYY'],
  'idbidirect.in': ['NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // IDFC First — account: DDMMYYYY, CC: DDMMYY
  'idfcfirstbank.com': ['DDMMYYYY', 'DDMMYY'],

  // Federal Bank — NAME4(UPPER)+DDMM
  'federalbank.co.in': ['NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // Bandhan Bank
  'bandhanbank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // RBL — NAME4(UPPER)+DDMMYY
  'rblbank.com': ['NAME4_UPPER+DDMMYY', 'NAME4_UPPER+DDMM', 'DDMMYYYY'],

  // South Indian Bank — name4(lower)+last4 account
  'southindianbank.com': ['NAME4_LOWER+LAST4', 'NAME4_LOWER+DDMM', 'DDMMYYYY'],

  // Karnataka Bank
  'karnatakabank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Karur Vysya Bank — CIF (can't generate)
  'kvb.co.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // City Union Bank
  'cityunionbank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Tamilnad Mercantile Bank
  'tmb.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Dhanlaxmi Bank
  'dfrbank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],
  'dhanlaxmibank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // DCB Bank
  'dcbbank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // CSB Bank
  'csb.co.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // J&K Bank
  'jkbank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Nainital Bank
  'nainitalbank.co.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // === SMALL FINANCE BANKS ===

  // AU SFB — account: CIF, CC: NAME4(UPPER)+last4
  'aubank.in': ['NAME4_UPPER+LAST4', 'DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Equitas — DDMM + NAME3(UPPER)
  'equitasbank.com': ['DDMM+NAME3_UPPER', 'DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Ujjivan SFB
  'ujjivansfb.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Jana SFB
  'janabank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // ESAF SFB
  'esafbank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Utkarsh SFB
  'utkarshbank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Suryoday SFB
  'suryodaybank.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // === PAYMENT BANKS ===

  // Airtel Payments Bank — DDMMYYYY + mobile (can't generate mobile)
  'airtelbank.com': ['DDMMYYYY'],

  // India Post Payments Bank
  'ippb.in': ['DDMMYYYY'],

  // Fino Payments Bank
  'finobank.com': ['DDMMYYYY'],

  // === FOREIGN BANKS ===

  // Citibank — NAME4 + DDMMM (3-letter month), case-insensitive
  'citibank.co.in': ['NAME4_UPPER+DDMMM', 'NAME4_LOWER+DDMMM', 'NAME4_UPPER+DDMM'],
  'citi.com': ['NAME4_UPPER+DDMMM', 'NAME4_LOWER+DDMMM', 'NAME4_UPPER+DDMM'],

  // Standard Chartered — DDMMYY + last 8 card digits (only have last 4)
  'sc.com': ['DDMMYY+LAST4', 'DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // HSBC — typically name+DOB combination
  'hsbc.co.in': ['NAME4_UPPER+DDMM', 'DDMMYYYY', 'NAME4_UPPER+DDMMYY'],

  // DBS — last 5 mobile + DDMMYY (can't generate mobile)
  'dbs.com': ['DDMMYY', 'DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Deutsche Bank
  'db.com': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Barclays
  'barclays.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // BNP Paribas
  'bnpparibas.co.in': ['DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // === CREDIT CARD ISSUERS ===

  // American Express — NAME4(UPPER)+DDMM
  'americanexpress.co.in': ['NAME4_UPPER+DDMM', 'NAME4_UPPER+DDMMYY'],

  // SBI Card — DDMMYYYY + last4
  'sbicard.com': ['DDMMYYYY+LAST4', 'DDMMYYYY', 'NAME4_UPPER+DDMM'],

  // Bajaj Finserv (RBL partnership) — NAME4(UPPER)+DDMMYY
  'bajajfinserv.in': ['NAME4_UPPER+DDMMYY', 'NAME4_UPPER+DDMM', 'DDMMYYYY'],
};

/**
 * Human-readable password hints for user display.
 * Maps sender domain → description of the password format.
 */
export const BANK_PASSWORD_HINTS: Record<string, string> = {
  // Public Sector
  'sbi.co.in': 'DOB (DDMMYYYY) or DOB + last 4 digits of card',
  'pnb.co.in': 'First 4 letters of name (lowercase) + DOB (DDMMYYYY)',
  'bankofbaroda.co.in': 'First 4 letters of name (lowercase) + DOB (DDMM)',
  'canarabank.in': 'First 4 letters of name (UPPER) + DOB (DDMM)',
  'canarabank.com': 'First 4 letters of name (UPPER) + DOB (DDMM)',
  'unionbankofindia.co.in': 'First 4 letters of name (UPPER) + DOB (DDMM)',
  'bankofindia.co.in': 'First 4 letters of name (lowercase) + DOB (DDMM)',
  'indianbank.in': 'Full bank account number',
  'centralbankofindia.co.in': 'Customer ID + @ + DOB (DDMMYYYY)',
  'iob.in': 'First 4 digits of CIF + last 4 digits of mobile',
  'ucobank.com': 'Registered 10-digit mobile number',
  'bankofmaharashtra.in': 'First 4 letters of name (lowercase) + DOB (DDMM)',
  'psbindia.com': 'DOB (DDMMYYYY)',
  // Private Sector
  'hdfcbank.net': 'Customer ID, or Name4(UPPER) + birth year, or Name4(UPPER) + last 4 card digits',
  'hdfcbank.com': 'Customer ID, or Name4(UPPER) + birth year, or Name4(UPPER) + last 4 card digits',
  'icicibank.com': 'name4(lowercase) + DOB (DDMM) for CC, NAME4(UPPER) + DOB (DDMM) for account',
  'axisbank.com': 'NAME4(UPPER) + DOB (DDMM) or NAME4(UPPER) + last 4 card digits',
  'kotak.com': 'name4(lowercase) + DOB (DDMM) for CC, CRN for account',
  'indusind.com': 'NAME4(UPPER) + DOB (DDMM)',
  'yesbank.in': 'CIF + DOB (DDMMYYYY)',
  'idbi.co.in': 'NAME4(UPPER) + DOB (DDMM) for CC, CIF for account',
  'idbidirect.in': 'NAME4(UPPER) + DOB (DDMM) for CC, CIF for account',
  'idfcfirstbank.com': 'DOB (DDMMYYYY) for account, DOB (DDMMYY) for CC',
  'federalbank.co.in': 'NAME4(UPPER) + DOB (DDMM)',
  'bandhanbank.com': 'DOB-based or Customer ID',
  'rblbank.com': 'NAME4(UPPER) + DOB (DDMMYY)',
  'southindianbank.com': 'name4(lowercase) + last 4 digits of account',
  'karnatakabank.com': 'DOB (DDMMYYYY)',
  'kvb.co.in': 'Customer ID (CIF)',
  'cityunionbank.com': 'DOB (DDMMYYYY)',
  'tmb.in': 'DOB (DDMMYYYY)',
  'dfrbank.com': 'DOB (DDMMYYYY)',
  'dhanlaxmibank.com': 'DOB (DDMMYYYY)',
  'dcbbank.com': 'DOB (DDMMYYYY)',
  'csb.co.in': 'DOB (DDMMYYYY)',
  'jkbank.com': 'DOB (DDMMYYYY)',
  'nainitalbank.co.in': 'DOB (DDMMYYYY)',
  // Small Finance Banks
  'aubank.in': 'CIF for account, NAME4(UPPER) + last 4 card digits for CC',
  'equitasbank.com': 'DOB (DDMM) + first 3 letters of name (UPPER)',
  'ujjivansfb.in': 'DOB (DDMMYYYY)',
  'janabank.com': 'DOB (DDMMYYYY)',
  'esafbank.com': 'DOB (DDMMYYYY)',
  'utkarshbank.com': 'DOB (DDMMYYYY)',
  'suryodaybank.com': 'DOB (DDMMYYYY)',
  // Foreign Banks
  'citibank.co.in': 'NAME4 + DOB (DDMMM, 3-letter month, e.g., JOHN01JAN)',
  'citi.com': 'NAME4 + DOB (DDMMM, 3-letter month)',
  'sc.com': 'DOB (DDMMYY) + last 8 card digits',
  'hsbc.co.in': 'Name + DOB combination (check email for instructions)',
  'dbs.com': 'Last 5 mobile digits + DOB (DDMMYY)',
  'db.com': 'DOB (DDMMYYYY)',
  'barclays.in': 'DOB (DDMMYYYY)',
  'bnpparibas.co.in': 'DOB (DDMMYYYY)',
  // Credit Card Issuers
  'americanexpress.co.in': 'NAME4(UPPER) + DOB (DDMM)',
  'sbicard.com': 'DOB (DDMMYYYY) + last 4 card digits',
  'bajajfinserv.in': 'NAME4(UPPER) + DOB (DDMMYY)',
};
