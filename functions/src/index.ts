import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { google } from 'googleapis';
import { GmailService, EmailMessage } from './services/gmailService';
import { GmailWatchService } from './services/gmailWatchService';
import { FinanceExtractionService } from './services/financeExtractionService';
import { PdfService } from './services/pdfService';
import { getFinanceQuery } from './utils/financeEmailQuery';
import { detectFinanceEmailType, isFinancialEmail } from './utils/financeDetector';
import { redactPII } from './utils/piiRedactor';
import { findDuplicate, markStatementConfirmed } from './utils/deduplication';
import { generatePasswordCandidates } from './utils/statementPasswordPatterns';
import { AIChatService } from './services/aiChatService';
import {
  ExtractedTransaction,
  AnalyzeFinanceRequest,
  AnalyzeFinanceResponse,
  AskFinanceAIRequest,
  FinanceEmailType,
  MonthlyAggregate,
  YearlyAggregate,
  CategoryBreakdown,
  MerchantBreakdown,
} from './types/financeTypes';

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

// Environment variables
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;

// ============================================
// HELPER: Auto-detect / create account
// ============================================

/**
 * Finds or creates a financial account document for a given
 * masked card/account number. Used during transaction processing
 * to automatically build the user's account list.
 */
async function getOrCreateAccount(
  userId: string,
  maskedNumber: string,
  provider: string,
  accountType: string
): Promise<string> {
  const db = admin.firestore();
  const accountsRef = db
    .collection('users')
    .doc(userId)
    .collection('accounts');

  // Check if account already exists
  const existing = await accountsRef
    .where('maskedNumber', '==', maskedNumber)
    .where('provider', '==', provider)
    .limit(1)
    .get();

  if (!existing.empty) return existing.docs[0].id;

  // Create new account
  const newDoc = await accountsRef.add({
    type: accountType,
    provider,
    maskedNumber,
    detectedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastTransactionAt: admin.firestore.FieldValue.serverTimestamp(),
    transactionCount: 0,
  });

  return newDoc.id;
}

// ============================================
// HELPER: Store a single extracted transaction
// ============================================

/**
 * Persists an extracted transaction to Firestore, handling
 * account auto-detection and deduplication.
 *
 * Returns the stored transaction or null if it was a duplicate.
 */
async function storeTransaction(
  userId: string,
  extracted: ExtractedTransaction,
  emailMessageId: string,
  emailDate: string,
  emailType: FinanceEmailType,
  source: 'batch' | 'webhook' | 'statement',
  pdfMeta?: { storagePath: string; filename: string }
): Promise<{ id: string; data: FirebaseFirestore.DocumentData } | null> {
  const db = admin.firestore();

  // Check for duplicates
  const existingId = await findDuplicate(userId, extracted, emailMessageId);
  if (existingId) {
    // If this came from a statement and the existing one was from an alert,
    // mark it as statement-confirmed for higher confidence
    if (source === 'statement') {
      await markStatementConfirmed(userId, existingId);
    }
    console.log(`Duplicate transaction found: ${existingId}, skipping`);
    return null;
  }

  // Auto-detect or create account
  const accountId = await getOrCreateAccount(
    userId,
    extracted.accountMasked,
    extracted.provider,
    extracted.accountType
  );

  // Build the Firestore document
  const txnDate = new Date(extracted.transactionDate);
  const now = admin.firestore.FieldValue.serverTimestamp();

  const txnData: Record<string, unknown> = {
    accountId,
    type: extracted.type,
    amount: extracted.amount,
    currency: extracted.currency || 'INR',
    amountINR: extracted.amountINR,
    merchant: extracted.merchant,
    merchantRaw: extracted.merchantRaw,
    category: extracted.category,
    subcategory: extracted.subcategory || null,
    date: admin.firestore.Timestamp.fromDate(txnDate),
    emailDate: admin.firestore.Timestamp.fromDate(new Date(emailDate)),
    emailMessageId,
    source,
    emailType,
    status: extracted.status || 'confirmed',
    referenceNumber: extracted.referenceNumber || null,
    balance: extracted.balance ?? null,
    statementConfirmed: source === 'statement',
    pdfStoragePath: pdfMeta?.storagePath || null,
    pdfFilename: pdfMeta?.filename || null,
    tags: [],
    createdAt: now,
    updatedAt: now,
  };

  const docRef = await db
    .collection('users')
    .doc(userId)
    .collection('transactions')
    .add(txnData);

  // Update account's lastTransactionAt and increment count
  await db
    .collection('users')
    .doc(userId)
    .collection('accounts')
    .doc(accountId)
    .update({
      lastTransactionAt: now,
      transactionCount: admin.firestore.FieldValue.increment(1),
    });

  return { id: docRef.id, data: txnData };
}

// ============================================
// HELPER: Process a single financial email
// ============================================

/**
 * Takes a single email message, detects its type, redacts PII,
 * extracts transaction(s), and stores them. Returns an array of
 * stored transactions (may be multiple for statement PDFs).
 */
async function processFinancialEmail(
  userId: string,
  message: EmailMessage,
  gmailService: GmailService,
  extractionService: FinanceExtractionService,
  source: 'batch' | 'webhook'
): Promise<ExtractedTransaction[]> {
  const emailType = detectFinanceEmailType(message.subject, message.from);

  // Skip non-financial or OTP emails
  if (emailType === 'otp_or_auth' || emailType === 'unknown') {
    return [];
  }

  const results: ExtractedTransaction[] = [];
  const redactedBody = redactPII(message.body);

  // Process PDF attachments from ANY financial email
  if (message.pdfAttachments.length > 0) {
    const pdfService = new PdfService();
    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    // Load user data once for all PDF processing
    const userDoc = await db.collection('users').doc(userId).get();
    const userData = userDoc.data();

    // Build password candidates once
    let passwords: string[] = [];
    if (userData?.dateOfBirth) {
      const dob = userData.dateOfBirth.toDate
        ? userData.dateOfBirth.toDate()
        : new Date(userData.dateOfBirth);

      const fromMatch = message.from.match(/<([^>]+)>/);
      const fromEmail = fromMatch ? fromMatch[1] : message.from.trim();
      const senderDomain = fromEmail.substring(fromEmail.lastIndexOf('@') + 1).toLowerCase();

      // Get known masked numbers for password generation
      const accountsSnap = await db.collection('users').doc(userId)
        .collection('accounts').get();
      const maskedNumbers = accountsSnap.docs
        .map((d) => d.data().maskedNumber as string)
        .filter(Boolean);

      const allCandidates: string[] = [];
      const baseCandidates = generatePasswordCandidates(
        '', senderDomain, dob, userData.displayName || undefined
      );
      allCandidates.push(...baseCandidates.map((c) => c.password));

      for (const masked of maskedNumbers) {
        const last4 = masked.replace(/[^0-9]/g, '').slice(-4);
        if (last4.length === 4) {
          const extraCandidates = generatePasswordCandidates(
            '', senderDomain, dob, userData.displayName || undefined, last4
          );
          for (const c of extraCandidates) {
            if (!allCandidates.includes(c.password)) {
              allCandidates.push(c.password);
            }
          }
        }
      }
      passwords = allCandidates;
    }

    for (const attachment of message.pdfAttachments) {
      try {
        // Fetch the PDF data from Gmail
        const rawPdfBuffer = await gmailService.fetchPdfAttachment(
          message.id,
          attachment.attachmentId
        );

        // Store raw PDF in Cloud Storage
        const storagePath = `users/${userId}/pdfs/${message.id}/${attachment.filename}`;
        try {
          await bucket.file(storagePath).save(rawPdfBuffer, {
            metadata: { contentType: 'application/pdf' },
          });
        } catch (storageErr) {
          console.warn(`Could not store PDF to Cloud Storage: ${storageErr}`);
        }

        // Decrypt PDF if needed using mupdf
        let pdfResult;
        try {
          pdfResult = await pdfService.processForClaude(rawPdfBuffer, passwords);
        } catch (pdfError: any) {
          const errorMsg = pdfError?.message || String(pdfError);
          const status = errorMsg.startsWith('password_required') ? 'failed_password'
            : errorMsg.startsWith('corrupt') ? 'failed_corrupt'
            : errorMsg.startsWith('empty') ? 'failed_empty'
            : 'failed_unknown';

          console.warn(`PDF processing failed for ${attachment.filename}: ${errorMsg}`);

          // Track failed PDF for re-processing later
          try {
            await db.collection('users').doc(userId).collection('storedPdfs').add({
              emailMessageId: message.id,
              filename: attachment.filename,
              storagePath,
              subject: message.subject,
              from: message.from,
              emailDate: message.date,
              emailType,
              status,
              passwordProtected: status === 'failed_password',
              transactionsExtracted: 0,
              pageCount: 0,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } catch (_) { /* ignore tracking errors */ }

          continue;
        }

        // Send decrypted PDF directly to Claude (no text extraction needed)
        console.log(
          `Sending PDF ${attachment.filename} (${pdfResult.pageCount} pages, ` +
          `encrypted=${pdfResult.wasEncrypted}) directly to Claude`
        );

        const statement = await extractionService.extractFromPdf(pdfResult.pdfBuffer);
        const txnCount = statement?.transactions?.length || 0;

        // Track PDF in Firestore
        try {
          await db.collection('users').doc(userId).collection('storedPdfs').add({
            emailMessageId: message.id,
            filename: attachment.filename,
            storagePath,
            subject: message.subject,
            from: message.from,
            emailDate: message.date,
            emailType,
            status: 'processed',
            passwordProtected: pdfResult.wasEncrypted,
            transactionsExtracted: txnCount,
            pageCount: pdfResult.pageCount,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) { /* ignore tracking errors */ }

        if (!statement || !statement.transactions.length) continue;

        // Store each transaction with PDF metadata
        const pdfMeta = { storagePath, filename: attachment.filename };
        for (const txn of statement.transactions) {
          if (txn.skip) continue;

          const stored = await storeTransaction(
            userId,
            txn,
            message.id,
            message.date,
            emailType,
            'statement',
            pdfMeta
          );

          if (stored) {
            results.push(txn);
          }
        }
      } catch (err) {
        console.error(`Error processing PDF attachment ${attachment.filename}:`, err);
        continue;
      }
    }
  }

  // Also process the email body text (alert / single-transaction)
  if (redactedBody.trim().length > 20) {
    const content = `Subject: ${message.subject}\nFrom: ${message.from}\nDate: ${message.date}\n\n${redactedBody}`;
    const extracted = await extractionService.extractTransaction(content, emailType);

    if (extracted && !extracted.skip) {
      const stored = await storeTransaction(
        userId,
        extracted,
        message.id,
        message.date,
        emailType,
        source
      );

      if (stored) {
        results.push(extracted);
      }
    }
  }

  return results;
}

// ============================================
// HELPER: Compute monthly aggregate
// ============================================

/**
 * Recomputes the monthly aggregate for a given YYYY-MM period.
 * Queries all transactions for that month, then writes/overwrites
 * the aggregate document.
 */
async function computeMonthlyAggregate(
  userId: string,
  yearMonth: string
): Promise<void> {
  const db = admin.firestore();
  const [yearStr, monthStr] = yearMonth.split('-');
  const year = parseInt(yearStr, 10);
  const month = parseInt(monthStr, 10);

  // Build date range for the month
  const startOfMonth = new Date(year, month - 1, 1);
  const endOfMonth = new Date(year, month, 0, 23, 59, 59, 999);

  const transactionsRef = db
    .collection('users')
    .doc(userId)
    .collection('transactions');

  const snapshot = await transactionsRef
    .where('date', '>=', admin.firestore.Timestamp.fromDate(startOfMonth))
    .where('date', '<=', admin.firestore.Timestamp.fromDate(endOfMonth))
    .get();

  let totalSpending = 0;
  let totalIncome = 0;
  const categoryBreakdown: CategoryBreakdown = {};
  const merchantTotals: Record<string, { total: number; count: number }> = {};
  const accountBreakdown: Record<string, { spending: number; income: number }> = {};
  let largestTransaction: { amount: number; merchant: string; date: string } | null = null;
  let smallestTransaction: { amount: number; merchant: string; date: string } | null = null;

  for (const doc of snapshot.docs) {
    const txn = doc.data();
    const amount = txn.amountINR || txn.amount || 0;
    const merchant = txn.merchant || 'Unknown';
    const category = txn.category || 'other';
    const accountId = txn.accountId || 'unknown';
    const txnDateStr = txn.date?.toDate?.()
      ? txn.date.toDate().toISOString().split('T')[0]
      : yearMonth + '-01';

    if (txn.type === 'debit') {
      totalSpending += amount;

      // Account breakdown
      if (!accountBreakdown[accountId]) {
        accountBreakdown[accountId] = { spending: 0, income: 0 };
      }
      accountBreakdown[accountId].spending += amount;

      // Largest / smallest (only debits for spending analysis)
      if (!largestTransaction || amount > largestTransaction.amount) {
        largestTransaction = { amount, merchant, date: txnDateStr };
      }
      if (!smallestTransaction || amount < smallestTransaction.amount) {
        smallestTransaction = { amount, merchant, date: txnDateStr };
      }
    } else {
      totalIncome += amount;

      if (!accountBreakdown[accountId]) {
        accountBreakdown[accountId] = { spending: 0, income: 0 };
      }
      accountBreakdown[accountId].income += amount;
    }

    // Category breakdown (all transactions)
    if (!categoryBreakdown[category]) {
      categoryBreakdown[category] = { total: 0, count: 0, avgTransaction: 0 };
    }
    categoryBreakdown[category].total += amount;
    categoryBreakdown[category].count += 1;

    // Merchant totals
    if (!merchantTotals[merchant]) {
      merchantTotals[merchant] = { total: 0, count: 0 };
    }
    merchantTotals[merchant].total += amount;
    merchantTotals[merchant].count += 1;
  }

  // Compute category averages
  for (const cat of Object.keys(categoryBreakdown)) {
    const { total, count } = categoryBreakdown[cat];
    categoryBreakdown[cat].avgTransaction = count > 0 ? total / count : 0;
  }

  // Build top-20 merchant breakdown
  const sortedMerchants = Object.entries(merchantTotals)
    .sort((a, b) => b[1].total - a[1].total)
    .slice(0, 20);
  const merchantBreakdown: MerchantBreakdown = {};
  for (const [name, data] of sortedMerchants) {
    merchantBreakdown[name] = data;
  }

  const aggregate: MonthlyAggregate = {
    period: yearMonth,
    type: 'monthly',
    totalSpending,
    totalIncome,
    netFlow: totalIncome - totalSpending,
    transactionCount: snapshot.size,
    categoryBreakdown,
    merchantBreakdown,
    accountBreakdown,
    largestTransaction,
    smallestTransaction,
    updatedAt: admin.firestore.FieldValue.serverTimestamp() as unknown as FirebaseFirestore.Timestamp,
  };

  const aggregateDocId = `monthly_${yearStr}_${monthStr.padStart(2, '0')}`;
  await db
    .collection('users')
    .doc(userId)
    .collection('financialAggregates')
    .doc(aggregateDocId)
    .set(aggregate, { merge: false });

  console.log(
    `Updated monthly aggregate ${aggregateDocId} for user ${userId}: ` +
    `${snapshot.size} txns, spending=${totalSpending}, income=${totalIncome}`
  );
}

// ============================================
// HELPER: Compute yearly aggregate
// ============================================

/**
 * Recomputes the yearly aggregate by reading all monthly aggregates
 * for the given year and rolling them up.
 */
async function computeYearlyAggregate(
  userId: string,
  year: number
): Promise<void> {
  const db = admin.firestore();
  const aggregatesRef = db
    .collection('users')
    .doc(userId)
    .collection('financialAggregates');

  // Read all monthly aggregates for this year
  const monthlyDocs = await aggregatesRef
    .where('type', '==', 'monthly')
    .where('period', '>=', `${year}-01`)
    .where('period', '<=', `${year}-12`)
    .get();

  let totalSpending = 0;
  let totalIncome = 0;
  let totalTransactionCount = 0;
  const categoryBreakdown: CategoryBreakdown = {};
  const merchantTotals: Record<string, { total: number; count: number }> = {};
  const monthlyTrend: Array<{ month: string; spending: number; income: number }> = [];

  for (const doc of monthlyDocs.docs) {
    const monthly = doc.data() as MonthlyAggregate;

    totalSpending += monthly.totalSpending || 0;
    totalIncome += monthly.totalIncome || 0;
    totalTransactionCount += monthly.transactionCount || 0;

    monthlyTrend.push({
      month: monthly.period,
      spending: monthly.totalSpending || 0,
      income: monthly.totalIncome || 0,
    });

    // Merge category breakdowns
    if (monthly.categoryBreakdown) {
      for (const [cat, data] of Object.entries(monthly.categoryBreakdown)) {
        if (!categoryBreakdown[cat]) {
          categoryBreakdown[cat] = { total: 0, count: 0, avgTransaction: 0 };
        }
        categoryBreakdown[cat].total += data.total;
        categoryBreakdown[cat].count += data.count;
      }
    }

    // Merge merchant breakdowns
    if (monthly.merchantBreakdown) {
      for (const [merchant, data] of Object.entries(monthly.merchantBreakdown)) {
        if (!merchantTotals[merchant]) {
          merchantTotals[merchant] = { total: 0, count: 0 };
        }
        merchantTotals[merchant].total += data.total;
        merchantTotals[merchant].count += data.count;
      }
    }
  }

  // Compute category averages
  for (const cat of Object.keys(categoryBreakdown)) {
    const { total, count } = categoryBreakdown[cat];
    categoryBreakdown[cat].avgTransaction = count > 0 ? total / count : 0;
  }

  // Top-20 merchants for yearly
  const sortedMerchants = Object.entries(merchantTotals)
    .sort((a, b) => b[1].total - a[1].total)
    .slice(0, 20);
  const merchantBreakdown: MerchantBreakdown = {};
  for (const [name, data] of sortedMerchants) {
    merchantBreakdown[name] = data;
  }

  // Sort monthly trend chronologically
  monthlyTrend.sort((a, b) => a.month.localeCompare(b.month));

  const aggregate: YearlyAggregate = {
    period: `${year}`,
    type: 'yearly',
    totalSpending,
    totalIncome,
    netFlow: totalIncome - totalSpending,
    transactionCount: totalTransactionCount,
    categoryBreakdown,
    merchantBreakdown,
    monthlyTrend,
    updatedAt: admin.firestore.FieldValue.serverTimestamp() as unknown as FirebaseFirestore.Timestamp,
  };

  await aggregatesRef.doc(`yearly_${year}`).set(aggregate, { merge: false });

  console.log(
    `Updated yearly aggregate yearly_${year} for user ${userId}: ` +
    `${totalTransactionCount} txns, spending=${totalSpending}, income=${totalIncome}`
  );
}

// ============================================
// AUTH & GMAIL SETUP FUNCTIONS
// ============================================

/**
 * Store refresh token for Gmail access
 * Exchanges auth code for refresh token and stores it in Firestore
 */
export const storeRefreshToken = functions
  .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
  })
  .https.onCall(async (data: { authCode: string }, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    const { authCode } = data;
    if (!authCode) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Auth code is required'
      );
    }

    if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Google OAuth credentials not configured'
      );
    }

    const userId = context.auth.uid;
    console.log(`Storing refresh token for user: ${userId}`);

    try {
      const oauth2Client = new google.auth.OAuth2(
        GOOGLE_CLIENT_ID,
        GOOGLE_CLIENT_SECRET,
        ''
      );

      const { tokens } = await oauth2Client.getToken(authCode);

      if (!tokens.refresh_token) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'No refresh token returned. User may need to revoke app access and re-authorize.'
        );
      }

      const db = admin.firestore();
      await db.collection('users').doc(userId).update({
        gmailRefreshToken: tokens.refresh_token,
        gmailTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true };
    } catch (error: any) {
      console.error('Error storing refresh token:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Failed to store refresh token: ${error.message}`
      );
    }
  });

/**
 * Set up Gmail watch for push notifications
 */
export const setupGmailWatch = functions
  .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
  })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    const userId = context.auth.uid;
    console.log(`Setting up Gmail watch for user: ${userId}`);

    try {
      const watchService = new GmailWatchService();
      const { historyId, expiration } = await watchService.setupWatch(userId);

      return { success: true, historyId, expiration };
    } catch (error: any) {
      console.error('Error setting up Gmail watch:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Failed to set up Gmail watch: ${error.message}`
      );
    }
  });

// ============================================
// 1. analyzeFinance — Batch Financial Email Processing
// ============================================

/**
 * Processes financial emails in batches using the Gmail API.
 *
 * For each email:
 *  - Detects the email type (transaction alert, statement, etc.)
 *  - Skips OTP/auth and unknown emails
 *  - Redacts PII before sending to AI
 *  - Extracts transaction data via Claude
 *  - Handles PDF statement attachments with password attempts
 *  - Deduplicates against existing transactions
 *  - Auto-detects and creates new accounts
 *  - Stores transactions in Firestore
 *  - Recomputes monthly/yearly aggregates for affected periods
 */
export const analyzeFinance = functions
  .runWith({
    timeoutSeconds: 540,
    memory: '512MB',
  })
  .https.onCall(async (data: AnalyzeFinanceRequest, context) => {
    // Authentication check — accept either Firebase Auth or userId in body
    const userId = context.auth?.uid || (data as any).userId;
    if (!userId) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    // Validate inputs
    const { accessToken, options } = data;
    if (!accessToken) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'accessToken is required'
      );
    }

    if (!ANTHROPIC_API_KEY) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'ANTHROPIC_API_KEY is not configured'
      );
    }

    const batchSize = options?.batchSize || 20;
    const batch = options?.batch || 1;
    const afterDate = options?.afterDate;
    const year = options?.year;

    console.log(
      `analyzeFinance: user=${userId}, batch=${batch}, batchSize=${batchSize}, afterDate=${afterDate}, year=${year}`
    );

    try {
      // Initialize services
      const gmailService = new GmailService(accessToken);
      const extractionService = new FinanceExtractionService(ANTHROPIC_API_KEY);

      // Build the finance query with date filtering
      const query = getFinanceQuery({ afterDate, year });

      // Fetch financial emails for this batch
      const { messages, moreBatches, totalEmails } = await gmailService.fetchEmails(query, {
        batchSize,
        batch,
      });

      console.log(
        `Fetched ${messages.length} emails (batch ${batch}), ` +
        `totalEmails=${totalEmails}, moreBatches=${moreBatches}`
      );

      // Process each email
      const allExtracted: ExtractedTransaction[] = [];
      const affectedMonths: Set<string> = new Set();

      for (const message of messages) {
        try {
          const extracted = await processFinancialEmail(
            userId,
            message,
            gmailService,
            extractionService,
            'batch'
          );

          for (const txn of extracted) {
            allExtracted.push(txn);

            // Track affected months for aggregate recomputation
            if (txn.transactionDate) {
              const [txnYear, txnMonth] = txn.transactionDate.split('-');
              affectedMonths.add(`${txnYear}-${txnMonth}`);
            }
          }
        } catch (err) {
          console.error(`Error processing email ${message.id}:`, err);
          continue;
        }
      }

      // Recompute aggregates for all affected months
      const affectedYears: Set<number> = new Set();
      for (const ym of affectedMonths) {
        try {
          await computeMonthlyAggregate(userId, ym);
          const yearNum = parseInt(ym.split('-')[0], 10);
          affectedYears.add(yearNum);
        } catch (err) {
          console.error(`Error computing monthly aggregate for ${ym}:`, err);
        }
      }

      // Recompute yearly aggregates
      for (const yr of affectedYears) {
        try {
          await computeYearlyAggregate(userId, yr);
        } catch (err) {
          console.error(`Error computing yearly aggregate for ${yr}:`, err);
        }
      }

      const response: AnalyzeFinanceResponse = {
        transactions: allExtracted,
        moreBatches,
        nextBatch: moreBatches ? batch + 1 : null,
        totalEmails,
        processedCount: messages.length,
      };

      console.log(
        `analyzeFinance complete: ${allExtracted.length} transactions extracted ` +
        `from ${messages.length} emails`
      );

      return response;
    } catch (error: any) {
      console.error('analyzeFinance error:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Failed to analyze financial emails: ${error.message}`
      );
    }
  });

// ============================================
// 2. gmailWebhook — Real-time Pub/Sub Processing
// ============================================

/**
 * Triggered by Gmail push notifications via Pub/Sub.
 *
 * When a new email arrives in a watched Gmail inbox, Google publishes
 * a message to our Pub/Sub topic. This function:
 *  1. Decodes the notification to get the user's email and historyId
 *  2. Finds the corresponding user in Firestore
 *  3. Fetches new message IDs since the last known historyId
 *  4. For each new message, checks if it's a financial email
 *  5. If financial: redacts PII, extracts transaction, deduplicates, stores
 *  6. Updates the stored historyId for the next notification
 */
export const gmailWebhook = functions
  .runWith({
    timeoutSeconds: 120,
    memory: '512MB',
  })
  .pubsub.topic('gmail-notifications')
  .onPublish(async (pubsubMessage) => {
    // Decode the Pub/Sub message
    let emailAddress: string;
    let historyId: string;

    try {
      const messageData = pubsubMessage.data
        ? JSON.parse(Buffer.from(pubsubMessage.data, 'base64').toString('utf-8'))
        : {};

      emailAddress = messageData.emailAddress;
      historyId = messageData.historyId;

      if (!emailAddress) {
        console.warn('gmailWebhook: No emailAddress in Pub/Sub message, ignoring');
        return;
      }

      console.log(
        `gmailWebhook: notification for ${emailAddress}, historyId=${historyId}`
      );
    } catch (err) {
      console.error('gmailWebhook: Failed to decode Pub/Sub message:', err);
      return;
    }

    // Find the user by email address in Firestore
    const db = admin.firestore();
    const usersQuery = await db
      .collection('users')
      .where('email', '==', emailAddress)
      .limit(1)
      .get();

    if (usersQuery.empty) {
      console.warn(`gmailWebhook: No user found for email ${emailAddress}`);
      return;
    }

    const userDoc = usersQuery.docs[0];
    const userId = userDoc.id;
    const userData = userDoc.data();
    const lastHistoryId = userData.gmailWatchHistoryId;

    if (!lastHistoryId) {
      console.warn(`gmailWebhook: No gmailWatchHistoryId for user ${userId}, skipping`);
      return;
    }

    if (!ANTHROPIC_API_KEY) {
      console.error('gmailWebhook: ANTHROPIC_API_KEY not configured');
      return;
    }

    try {
      const watchService = new GmailWatchService();

      // Get new message IDs since last history checkpoint
      const newMessageIds = await watchService.getNewMessages(userId, lastHistoryId);
      console.log(
        `gmailWebhook: ${newMessageIds.length} new messages for user ${userId}`
      );

      if (newMessageIds.length === 0) {
        // Update historyId even if no new messages (avoids replaying old history)
        await db.collection('users').doc(userId).update({
          gmailWatchHistoryId: historyId,
        });
        return;
      }

      // Get a fresh access token for fetching email content
      const accessToken = await watchService.getAccessToken(userId);
      const gmailService = new GmailService(accessToken);
      const extractionService = new FinanceExtractionService(ANTHROPIC_API_KEY);

      const affectedMonths: Set<string> = new Set();

      for (const messageId of newMessageIds) {
        try {
          // Fetch the full email
          const message = await gmailService.fetchMessageById(messageId);
          if (!message) {
            console.warn(`gmailWebhook: Could not fetch message ${messageId}`);
            continue;
          }

          // Quick check: is this a financial email?
          if (!isFinancialEmail(message.subject, message.from)) {
            continue;
          }

          console.log(
            `gmailWebhook: Processing financial email ${messageId}: "${message.subject}"`
          );

          // Process the financial email
          const extracted = await processFinancialEmail(
            userId,
            message,
            gmailService,
            extractionService,
            'webhook'
          );

          // Track affected months
          for (const txn of extracted) {
            if (txn.transactionDate) {
              const [txnYear, txnMonth] = txn.transactionDate.split('-');
              affectedMonths.add(`${txnYear}-${txnMonth}`);
            }
          }
        } catch (err) {
          console.error(`gmailWebhook: Error processing message ${messageId}:`, err);
          continue;
        }
      }

      // Recompute aggregates for affected months
      const affectedYears: Set<number> = new Set();
      for (const ym of affectedMonths) {
        try {
          await computeMonthlyAggregate(userId, ym);
          affectedYears.add(parseInt(ym.split('-')[0], 10));
        } catch (err) {
          console.error(`gmailWebhook: Error computing aggregate for ${ym}:`, err);
        }
      }

      for (const yr of affectedYears) {
        try {
          await computeYearlyAggregate(userId, yr);
        } catch (err) {
          console.error(`gmailWebhook: Error computing yearly aggregate for ${yr}:`, err);
        }
      }

      // Update the historyId to the latest value
      await db.collection('users').doc(userId).update({
        gmailWatchHistoryId: historyId,
      });

      console.log(`gmailWebhook: Finished processing for user ${userId}`);
    } catch (error: any) {
      console.error(`gmailWebhook: Error for user ${userId}:`, error);

      // Still try to update historyId so we don't replay on next notification
      try {
        await db.collection('users').doc(userId).update({
          gmailWatchHistoryId: historyId,
        });
      } catch (_updateErr) {
        console.error('gmailWebhook: Failed to update historyId after error');
      }
    }
  });

// ============================================
// 3. onTransactionWrite — Firestore Trigger
// ============================================

/**
 * Fires whenever a transaction document is created, updated, or deleted.
 *
 * Recomputes the monthly and yearly aggregates for the affected period
 * so that dashboards always show up-to-date totals and breakdowns.
 */
export const onTransactionWrite = functions
  .runWith({
    timeoutSeconds: 60,
    memory: '512MB',
  })
  .firestore.document('users/{userId}/transactions/{transactionId}')
  .onWrite(async (change, context) => {
    const userId = context.params.userId;

    // Determine the affected date(s)
    // On delete, use the "before" data; on create/update, use the "after" data
    const affectedMonths: Set<string> = new Set();

    // Check the "after" snapshot (exists for create and update)
    if (change.after.exists) {
      const afterData = change.after.data();
      if (afterData?.date) {
        const d = afterData.date.toDate ? afterData.date.toDate() : new Date(afterData.date);
        const ym = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        affectedMonths.add(ym);
      }
    }

    // Check the "before" snapshot (exists for update and delete)
    if (change.before.exists) {
      const beforeData = change.before.data();
      if (beforeData?.date) {
        const d = beforeData.date.toDate ? beforeData.date.toDate() : new Date(beforeData.date);
        const ym = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        affectedMonths.add(ym);
      }
    }

    if (affectedMonths.size === 0) {
      console.warn(
        `onTransactionWrite: No date found on transaction ${context.params.transactionId}, skipping aggregation`
      );
      return;
    }

    console.log(
      `onTransactionWrite: Recomputing aggregates for user ${userId}, months: ${[...affectedMonths].join(', ')}`
    );

    // Recompute monthly aggregates
    const affectedYears: Set<number> = new Set();
    for (const ym of affectedMonths) {
      try {
        await computeMonthlyAggregate(userId, ym);
        affectedYears.add(parseInt(ym.split('-')[0], 10));
      } catch (err) {
        console.error(`onTransactionWrite: Error computing monthly aggregate for ${ym}:`, err);
      }
    }

    // Recompute yearly aggregates
    for (const yr of affectedYears) {
      try {
        await computeYearlyAggregate(userId, yr);
      } catch (err) {
        console.error(`onTransactionWrite: Error computing yearly aggregate for ${yr}:`, err);
      }
    }

    // Update account transaction count if this was a delete
    if (!change.after.exists && change.before.exists) {
      const beforeData = change.before.data();
      if (beforeData?.accountId) {
        try {
          const db = admin.firestore();
          await db
            .collection('users')
            .doc(userId)
            .collection('accounts')
            .doc(beforeData.accountId)
            .update({
              transactionCount: admin.firestore.FieldValue.increment(-1),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } catch (err) {
          console.error(
            `onTransactionWrite: Error decrementing account count for ${beforeData.accountId}:`,
            err
          );
        }
      }
    }
  });

// ============================================
// 4. recomputeAggregates — Admin Recomputation
// ============================================

/**
 * Recomputes ALL financial aggregates for a user.
 *
 * This is useful for:
 *  - Initial setup after importing historical transactions
 *  - Recovery after data migration or corruption
 *  - Correcting drift from missed trigger events
 *
 * Scans all transactions for the user, groups them by month,
 * and rebuilds every monthly and yearly aggregate from scratch.
 */
export const recomputeAggregates = functions
  .runWith({
    timeoutSeconds: 540,
    memory: '1GB',
  })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    const userId = context.auth.uid;
    console.log(`recomputeAggregates: Starting full recomputation for user ${userId}`);

    try {
      const db = admin.firestore();

      // Fetch ALL transactions for this user
      const transactionsRef = db
        .collection('users')
        .doc(userId)
        .collection('transactions');

      const allTxns = await transactionsRef.get();

      if (allTxns.empty) {
        console.log(`recomputeAggregates: No transactions found for user ${userId}`);
        return { success: true, monthsProcessed: 0, yearsProcessed: 0 };
      }

      // Group transaction dates into unique YYYY-MM periods
      const months: Set<string> = new Set();
      for (const doc of allTxns.docs) {
        const txn = doc.data();
        if (txn.date) {
          const d = txn.date.toDate ? txn.date.toDate() : new Date(txn.date);
          const ym = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
          months.add(ym);
        }
      }

      console.log(
        `recomputeAggregates: Found ${allTxns.size} transactions across ${months.size} months`
      );

      // Delete existing aggregates to start fresh
      const aggregatesRef = db
        .collection('users')
        .doc(userId)
        .collection('financialAggregates');

      const existingAggregates = await aggregatesRef.get();
      const deleteBatch = db.batch();
      for (const doc of existingAggregates.docs) {
        deleteBatch.delete(doc.ref);
      }
      await deleteBatch.commit();

      // Recompute monthly aggregates
      const years: Set<number> = new Set();
      for (const ym of months) {
        await computeMonthlyAggregate(userId, ym);
        years.add(parseInt(ym.split('-')[0], 10));
      }

      // Recompute yearly aggregates
      for (const yr of years) {
        await computeYearlyAggregate(userId, yr);
      }

      // Also recompute account transaction counts
      const accountCounts: Record<string, number> = {};
      for (const doc of allTxns.docs) {
        const txn = doc.data();
        if (txn.accountId) {
          accountCounts[txn.accountId] = (accountCounts[txn.accountId] || 0) + 1;
        }
      }

      const accountsRef = db
        .collection('users')
        .doc(userId)
        .collection('accounts');

      for (const [accountId, count] of Object.entries(accountCounts)) {
        try {
          await accountsRef.doc(accountId).update({
            transactionCount: count,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (err) {
          console.warn(
            `recomputeAggregates: Could not update account ${accountId} count:`,
            err
          );
        }
      }

      console.log(
        `recomputeAggregates: Completed for user ${userId}. ` +
        `${months.size} months, ${years.size} years recomputed.`
      );

      return {
        success: true,
        monthsProcessed: months.size,
        yearsProcessed: years.size,
        totalTransactions: allTxns.size,
      };
    } catch (error: any) {
      console.error('recomputeAggregates error:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Failed to recompute aggregates: ${error.message}`
      );
    }
  });

// ============================================
// 5. askFinanceAI — AI Chat
// ============================================

/**
 * Two-call AI chat pattern:
 *  1. Classify the question to determine what data is needed (Claude Haiku)
 *  2. Load relevant data from Firestore (no AI)
 *  3. Generate answer with focused context (Claude Sonnet)
 *
 * Includes rate limiting (30/hour, 200/day) and session management.
 */
export const askFinanceAI = functions
  .runWith({
    timeoutSeconds: 60,
    memory: '512MB',
  })
  .https.onCall(async (data: AskFinanceAIRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    const userId = context.auth.uid;
    const { question, sessionId } = data;

    if (!question || typeof question !== 'string' || question.trim().length === 0) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'question is required and must be a non-empty string'
      );
    }

    if (!ANTHROPIC_API_KEY) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'ANTHROPIC_API_KEY is not configured'
      );
    }

    console.log(`askFinanceAI: user=${userId}, question="${question.substring(0, 80)}"`);

    try {
      const chatService = new AIChatService(ANTHROPIC_API_KEY);
      const result = await chatService.askQuestion(userId, question.trim(), sessionId);

      return {
        answer: result.answer,
        sessionId: result.sessionId,
      };
    } catch (error: any) {
      // Re-throw HttpsErrors as-is (e.g., rate limit errors)
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      console.error('askFinanceAI error:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Failed to process question: ${error.message}`
      );
    }
  });
