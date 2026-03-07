/**
 * Gmail Search Query Builder for Indian Financial Emails
 *
 * Builds a Gmail API `q` parameter string that targets transactional
 * emails from Indian banks, credit card issuers, and UPI/payment apps,
 * while excluding OTP / authentication messages.
 */

// ============================================
// Sender addresses by category
// ============================================

const BANK_SENDERS: string[] = [
  // === PUBLIC SECTOR BANKS (12) ===
  // SBI
  'alerts@sbi.co.in',
  'donotreply@sbi.co.in',
  // Punjab National Bank
  'alerts@pnb.co.in',
  'noreply@pnb.co.in',
  // Bank of Baroda
  'alerts@bankofbaroda.co.in',
  'noreply@bankofbaroda.co.in',
  // Canara Bank
  'alerts@canarabank.com',
  'alerts@canarabank.in',
  // Union Bank of India
  'alerts@unionbankofindia.co.in',
  'noreply@unionbankofindia.co.in',
  // Bank of India
  'alerts@bankofindia.co.in',
  'noreply@bankofindia.co.in',
  // Indian Bank
  'alerts@indianbank.in',
  'noreply@indianbank.in',
  // Central Bank of India
  'alerts@centralbankofindia.co.in',
  'noreply@centralbankofindia.co.in',
  // Indian Overseas Bank
  'alerts@iob.in',
  'noreply@iob.in',
  // UCO Bank
  'alerts@ucobank.com',
  'noreply@ucobank.com',
  // Bank of Maharashtra
  'alerts@bankofmaharashtra.in',
  'noreply@bankofmaharashtra.in',
  // Punjab & Sind Bank
  'alerts@psbindia.com',
  'noreply@psbindia.com',

  // === PRIVATE SECTOR BANKS (21) ===
  // HDFC Bank
  'alerts@hdfcbank.net',
  'noreply@hdfcbank.com',
  // ICICI Bank
  'alerts@icicibank.com',
  'noreply@icicibank.com',
  // Axis Bank
  'alerts@axisbank.com',
  'noreply@axisbank.com',
  // Kotak Mahindra Bank
  'alerts@kotak.com',
  'noreply@kotak.com',
  // IndusInd Bank
  'alerts@indusind.com',
  'noreply@indusind.com',
  // Yes Bank
  'alerts@yesbank.in',
  'noreply@yesbank.in',
  // IDBI Bank
  'alerts@idbi.co.in',
  'noreply@idbidirect.in',
  // IDFC First Bank
  'alerts@idfcfirstbank.com',
  'noreply@idfcfirstbank.com',
  // Federal Bank
  'alerts@federalbank.co.in',
  'noreply@federalbank.co.in',
  // Bandhan Bank
  'alerts@bandhanbank.com',
  'noreply@bandhanbank.com',
  // RBL Bank
  'alerts@rblbank.com',
  'noreply@rblbank.com',
  // South Indian Bank
  'alerts@southindianbank.com',
  'noreply@southindianbank.com',
  // Karnataka Bank
  'alerts@karnatakabank.com',
  'noreply@karnatakabank.com',
  // Karur Vysya Bank
  'alerts@kvb.co.in',
  'noreply@kvb.co.in',
  // City Union Bank
  'alerts@cityunionbank.com',
  'noreply@cityunionbank.com',
  // Tamilnad Mercantile Bank
  'alerts@tmb.in',
  'noreply@tmb.in',
  // Dhanlaxmi Bank
  'alerts@dfrbank.com',
  'noreply@dhanlaxmibank.com',
  // DCB Bank
  'alerts@dcbbank.com',
  'noreply@dcbbank.com',
  // CSB Bank (Catholic Syrian Bank)
  'alerts@csb.co.in',
  'noreply@csb.co.in',
  // Jammu & Kashmir Bank
  'alerts@jkbank.com',
  'noreply@jkbank.com',
  // Nainital Bank
  'alerts@nainitalbank.co.in',
  'noreply@nainitalbank.co.in',

  // === SMALL FINANCE BANKS (11) ===
  // AU Small Finance Bank
  'alerts@aubank.in',
  'noreply@aubank.in',
  // Equitas Small Finance Bank
  'alerts@equitasbank.com',
  'noreply@equitasbank.com',
  // Ujjivan Small Finance Bank
  'alerts@ujjivansfb.in',
  'noreply@ujjivansfb.in',
  // Jana Small Finance Bank
  'alerts@janabank.com',
  'noreply@janabank.com',
  // ESAF Small Finance Bank
  'alerts@esafbank.com',
  'noreply@esafbank.com',
  // Utkarsh Small Finance Bank
  'alerts@utkarshbank.com',
  'noreply@utkarshbank.com',
  // Suryoday Small Finance Bank
  'alerts@suryodaybank.com',
  'noreply@suryodaybank.com',
  // Capital Small Finance Bank
  'alerts@capitalbank.co.in',
  'noreply@capitalbank.co.in',
  // North East Small Finance Bank
  'alerts@nesfb.com',
  'noreply@nesfb.com',
  // Shivalik Small Finance Bank
  'alerts@shivalikbank.com',
  'noreply@shivalikbank.com',
  // Unity Small Finance Bank
  'alerts@unitybank.in',
  'noreply@unitybank.in',

  // === PAYMENT BANKS ===
  // Airtel Payments Bank
  'alerts@airtelbank.com',
  'noreply@airtelbank.com',
  // India Post Payments Bank
  'alerts@ippb.in',
  'noreply@ippb.in',
  // Fino Payments Bank
  'alerts@finobank.com',
  'noreply@finobank.com',
  // Jio Payments Bank
  'noreply@jiopaymentbank.com',

  // === FOREIGN BANKS IN INDIA ===
  // HSBC
  'alerts@hsbc.co.in',
  'noreply@hsbc.co.in',
  // Standard Chartered
  'alerts@sc.com',
  'noreply@sc.com',
  // DBS Bank
  'alerts@dbs.com',
  'noreply@dbs.com',
  // Deutsche Bank
  'alerts@db.com',
  // Barclays
  'alerts@barclays.in',
  // BNP Paribas
  'alerts@bnpparibas.co.in',
  // Citibank
  'alerts@citibank.co.in',
  'noreply@citi.com',
];

const UPI_PAYMENT_SENDERS: string[] = [
  // PhonePe
  'noreply@phonepe.com',
  // Paytm
  'noreply@paytm.com',
  // CRED
  'noreply@cred.club',
  // Amazon Pay
  'noreply@amazonpay.in',
  // Jupiter
  'noreply@jupiter.money',
  // Fi Money
  'noreply@fi.money',
  // Niyo
  'noreply@goniyo.com',
  // Freo
  'noreply@freo.money',
  // Simpl
  'noreply@getsimpl.com',
  // LazyPay
  'noreply@lazypay.in',
];

const CREDIT_CARD_SENDERS: string[] = [
  // American Express
  'alerts@americanexpress.co.in',
  'noreply@americanexpress.co.in',
  // SBI Card
  'alerts@sbicard.com',
  'noreply@sbicard.com',
  // NPCI / RuPay
  'alerts@npci.org.in',
  // Bajaj Finserv
  'alerts@bajajfinserv.in',
  'noreply@bajajfinserv.in',
  // OneCard
  'noreply@getonecard.com',
  // Slice
  'noreply@sliceit.com',
];

// Google Pay uses noreply@google.com which is too broad;
// we handle it via subject keyword matching instead.
const GOOGLE_PAY_SENDER = 'noreply@google.com';

// ============================================
// Subject keywords for financial transactions
// ============================================

const SUBJECT_KEYWORDS: string[] = [
  'debited',
  'credited',
  'transaction',
  'payment',
  'spent',
  'purchased',
  'received',
  'transferred',
  'EMI',
  'statement',
  'refund',
  'salary',
  'UPI',
  'NEFT',
  'RTGS',
  'IMPS',
  'withdrawal',
  'deposit',
  'balance',
  'autopay',
  'mandate',
  'bill payment',
  'credit card',
  'debit card',
  'account',
  'bank',
];

// ============================================
// Exclusion terms (OTP / auth noise)
// ============================================

const EXCLUSION_TERMS: string[] = [
  'OTP',
  '"one time password"',
  '"verification code"',
  '"secure code"',
  'login',
  '"password reset"',
];

// ============================================
// Query builder
// ============================================

/**
 * Build a Gmail search query string for Indian financial emails.
 *
 * The query is structured as:
 *   ( <sender clauses> OR <subject keyword clauses> )
 *   AND NOT ( <exclusion clauses> )
 *   AND optional date range
 *
 * @param options - Optional filtering options.
 *   - `afterDate`: Date string in `YYYY/MM/DD` format (e.g. `2025/09/05`).
 *   - `year`: Year to restrict results (e.g. 2026). Ignored if `afterDate` is set.
 * @returns Gmail query string suitable for `gmail.users.messages.list` `q` param.
 */
export function getFinanceQuery(options?: { afterDate?: string; year?: number }): string {
  // --- Sender clauses ---
  const allDirectSenders = [
    ...BANK_SENDERS,
    ...UPI_PAYMENT_SENDERS,
    ...CREDIT_CARD_SENDERS,
  ];

  const senderClauses = allDirectSenders.map((s) => `from:${s}`);

  // Google Pay: use from + subject combination
  const googlePayClause = `(from:${GOOGLE_PAY_SENDER} subject:(payment OR UPI OR "money sent" OR "money received"))`;

  // --- Subject keyword clauses ---
  const subjectClause = `subject:(${SUBJECT_KEYWORDS.join(' OR ')})`;

  // --- Combine inclusion logic ---
  // Match emails that come from known financial senders OR have financial subject keywords
  // Google Pay is a special case since its sender is generic
  const inclusionParts = [
    ...senderClauses,
    googlePayClause,
    subjectClause,
  ];
  const inclusionQuery = `(${inclusionParts.join(' OR ')})`;

  // --- Exclusion clause ---
  const exclusionQuery = `-{${EXCLUSION_TERMS.join(' ')}}`;

  // --- Date range ---
  let dateClause = '';
  if (options?.afterDate) {
    dateClause = ` after:${options.afterDate}`;
  } else if (options?.year) {
    dateClause = ` after:${options.year}/01/01 before:${options.year + 1}/01/01`;
  }

  return `${inclusionQuery} ${exclusionQuery}${dateClause}`;
}
