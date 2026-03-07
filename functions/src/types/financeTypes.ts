/**
 * Financial Email Intelligence System - Type Definitions
 *
 * Comprehensive TypeScript interfaces for transaction extraction,
 * Firestore documents, aggregates, chat, and API contracts.
 */

// ============================================
// Core Enums / Union Types
// ============================================

export type TransactionCategory =
  | 'food'
  | 'transport'
  | 'shopping'
  | 'utilities'
  | 'entertainment'
  | 'health'
  | 'education'
  | 'travel'
  | 'groceries'
  | 'fuel'
  | 'investment'
  | 'salary'
  | 'emi'
  | 'transfer'
  | 'rent'
  | 'insurance'
  | 'other';

export type AccountType = 'bank_account' | 'credit_card' | 'upi' | 'wallet';

export type FinanceEmailType =
  | 'transaction_alert'
  | 'upi_alert'
  | 'cc_alert'
  | 'cc_statement'
  | 'bank_statement'
  | 'salary_credit'
  | 'emi_debit'
  | 'investment'
  | 'refund'
  | 'otp_or_auth'
  | 'unknown';

export type TransactionStatus = 'confirmed' | 'pending' | 'failed' | 'refunded';

// ============================================
// AI Extraction Interfaces
// ============================================

/**
 * Single transaction extracted from a financial email by AI.
 * `skip` is true when the email is not a valid financial transaction
 * (e.g. promotional, OTP, or irrelevant).
 */
export interface ExtractedTransaction {
  skip?: boolean;
  type: 'debit' | 'credit';
  amount: number;
  currency: string;
  amountINR: number;
  accountMasked: string;          // e.g. "XX1234"
  accountType: AccountType;
  provider: string;               // e.g. "HDFC Bank"
  merchant: string;               // normalized merchant name
  merchantRaw: string;            // merchant name as it appears in email
  category: TransactionCategory;
  subcategory?: string;
  transactionDate: string;        // YYYY-MM-DD
  transactionTime?: string;       // HH:mm
  referenceNumber?: string;
  balance?: number;
  status: TransactionStatus;
}

/**
 * Extracted from credit card / bank statement PDFs.
 * Contains an array of transactions plus statement-level metadata.
 */
export interface ExtractedStatement {
  transactions: ExtractedTransaction[];
  statementPeriod: { from: string; to: string };
  accountMasked: string;
  provider: string;
  totalDue?: number;
  minimumDue?: number;
  dueDate?: string;
}

// ============================================
// Firestore Document Interfaces
// ============================================

/**
 * Represents a detected financial account.
 * Stored at: users/{uid}/finance/data/accounts/{accountId}
 */
export interface Account {
  type: AccountType;
  provider: string;
  maskedNumber: string;
  nickname?: string;
  detectedAt: FirebaseFirestore.Timestamp;
  lastTransactionAt: FirebaseFirestore.Timestamp;
  transactionCount: number;
}

/**
 * Represents a single financial transaction.
 * Stored at: users/{uid}/finance/data/transactions/{transactionId}
 */
export interface Transaction {
  accountId: string;
  type: 'debit' | 'credit';
  amount: number;
  currency: string;
  amountINR: number;
  merchant: string;
  merchantRaw: string;
  category: TransactionCategory;
  subcategory?: string;
  date: FirebaseFirestore.Timestamp;
  emailDate: FirebaseFirestore.Timestamp;
  emailMessageId: string;
  source: 'batch' | 'webhook' | 'statement';
  emailType: FinanceEmailType;
  status: TransactionStatus;
  refundOf?: string;
  statementConfirmed: boolean;
  tags: string[];
  notes?: string;
  referenceNumber?: string;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

// ============================================
// Aggregate Interfaces
// ============================================

export interface CategoryBreakdown {
  [category: string]: {
    total: number;
    count: number;
    avgTransaction: number;
  };
}

export interface MerchantBreakdown {
  [merchant: string]: {
    total: number;
    count: number;
  };
}

/**
 * Monthly spending/income aggregate.
 * Stored at: users/{uid}/finance/data/aggregates/monthly_{YYYY-MM}
 */
export interface MonthlyAggregate {
  period: string;                 // e.g. "2026-03"
  type: 'monthly';
  totalSpending: number;
  totalIncome: number;
  netFlow: number;
  transactionCount: number;
  categoryBreakdown: CategoryBreakdown;
  merchantBreakdown: MerchantBreakdown;   // top 20
  accountBreakdown: { [accountId: string]: { spending: number; income: number } };
  largestTransaction: { amount: number; merchant: string; date: string } | null;
  smallestTransaction: { amount: number; merchant: string; date: string } | null;
  updatedAt: FirebaseFirestore.Timestamp;
}

/**
 * Yearly spending/income aggregate.
 * Stored at: users/{uid}/finance/data/aggregates/yearly_{YYYY}
 */
export interface YearlyAggregate {
  period: string;                 // e.g. "2026"
  type: 'yearly';
  totalSpending: number;
  totalIncome: number;
  netFlow: number;
  transactionCount: number;
  categoryBreakdown: CategoryBreakdown;
  merchantBreakdown: MerchantBreakdown;
  monthlyTrend: Array<{ month: string; spending: number; income: number }>;
  updatedAt: FirebaseFirestore.Timestamp;
}

/**
 * A single detected recurring payment pattern.
 */
export interface RecurringPattern {
  merchant: string;
  amount: number;
  frequency: 'weekly' | 'monthly' | 'quarterly' | 'yearly';
  lastSeen: string;
  nextExpected: string;
  category: TransactionCategory;
}

/**
 * Collection of recurring payment patterns.
 * Stored at: users/{uid}/finance/data/aggregates/recurring
 */
export interface RecurringAggregate {
  patterns: RecurringPattern[];
  updatedAt: FirebaseFirestore.Timestamp;
}

// ============================================
// Chat Interfaces
// ============================================

export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp: FirebaseFirestore.Timestamp;
}

/**
 * A finance AI chat session.
 * Stored at: users/{uid}/finance/data/chatSessions/{sessionId}
 */
export interface ChatSession {
  createdAt: FirebaseFirestore.Timestamp;
  lastMessageAt: FirebaseFirestore.Timestamp;
  title: string;
  messages: ChatMessage[];
}

// ============================================
// API Request / Response Interfaces
// ============================================

export interface AnalyzeFinanceRequest {
  accessToken: string;
  options?: {
    batchSize?: number;
    batch?: number;
    year?: number;
    afterDate?: string;
  };
}

export interface AnalyzeFinanceResponse {
  transactions: ExtractedTransaction[];
  moreBatches: boolean;
  nextBatch: number | null;
  totalEmails: number;
  processedCount: number;
}

export interface AskFinanceAIRequest {
  question: string;
  sessionId?: string;
}

export interface AskFinanceAIResponse {
  answer: string;
  sessionId: string;
}

// ============================================
// Question Classification (AI two-call pattern)
// ============================================

/**
 * Output of the first AI call: classifies what data is needed
 * to answer the user's finance question, so the second call
 * receives only the relevant Firestore data.
 */
export interface QuestionClassification {
  dataNeeded: Array<
    | 'monthly_aggregate'
    | 'yearly_aggregate'
    | 'category_transactions'
    | 'merchant_transactions'
    | 'account_transactions'
    | 'recent_transactions'
    | 'recurring_patterns'
    | 'specific_date_range'
    | 'comparison'
  >;
  parameters: {
    months?: string[];
    categories?: TransactionCategory[];
    merchants?: string[];
    accountId?: string;
    dateRange?: { from: string; to: string };
    limit?: number;
    comparisonPeriods?: { period1: string; period2: string };
  };
  questionType:
    | 'aggregate_query'
    | 'transaction_list'
    | 'comparison'
    | 'trend'
    | 'recommendation'
    | 'general';
}
