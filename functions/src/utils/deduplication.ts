import * as admin from 'firebase-admin';
import { ExtractedTransaction } from '../types/financeTypes';

/**
 * Check if a transaction already exists (is a duplicate).
 * Uses a three-layer deduplication strategy:
 *   1. Exact email message ID match
 *   2. Reference number match
 *   3. Fuzzy match — same amount + date within +/-1 day + similar merchant
 *
 * Returns the existing transaction ID if a duplicate is found, null if new.
 */
export async function findDuplicate(
  userId: string,
  transaction: ExtractedTransaction,
  emailMessageId: string
): Promise<string | null> {
  const db = admin.firestore();
  const txnRef = db
    .collection('users')
    .doc(userId)
    .collection('transactions');

  // ---- Layer 1: Exact email message ID match ----
  const exactQuery = await txnRef
    .where('emailMessageId', '==', emailMessageId)
    .limit(1)
    .get();
  if (!exactQuery.empty) {
    return exactQuery.docs[0].id;
  }

  // ---- Layer 2: Reference number match ----
  if (transaction.referenceNumber) {
    const refQuery = await txnRef
      .where('referenceNumber', '==', transaction.referenceNumber)
      .limit(1)
      .get();

    if (!refQuery.empty) {
      return refQuery.docs[0].id;
    }
  }

  // ---- Layer 3: Fuzzy match ----
  // Same amount + date within +/-1 day + similar merchant name
  const txnDate = new Date(transaction.transactionDate);
  const dayBefore = new Date(txnDate);
  dayBefore.setDate(dayBefore.getDate() - 1);
  const dayAfter = new Date(txnDate);
  dayAfter.setDate(dayAfter.getDate() + 1);

  const fuzzyQuery = await txnRef
    .where('amount', '==', transaction.amount)
    .where('date', '>=', admin.firestore.Timestamp.fromDate(dayBefore))
    .where('date', '<=', admin.firestore.Timestamp.fromDate(dayAfter))
    .get();

  for (const doc of fuzzyQuery.docs) {
    const existing = doc.data();
    if (merchantSimilarity(existing.merchant || '', transaction.merchant || '') > 0.6) {
      return doc.id;
    }
  }

  return null;
}

/**
 * Compute similarity between two merchant names using Jaccard similarity
 * on lowercased word tokens. Returns a value between 0 and 1.
 *
 * Examples:
 *   merchantSimilarity("Swiggy", "SWIGGY")                => 1.0
 *   merchantSimilarity("Amazon Pay", "Amazon")             => 0.5
 *   merchantSimilarity("Zomato Online", "Zomato Online Pvt Ltd") => 0.5
 */
function merchantSimilarity(a: string, b: string): number {
  const tokenize = (s: string): Set<string> => {
    const words = s
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, '')
      .split(/\s+/)
      .filter((w) => w.length > 0);
    return new Set(words);
  };

  const setA = tokenize(a);
  const setB = tokenize(b);

  if (setA.size === 0 && setB.size === 0) return 1;
  if (setA.size === 0 || setB.size === 0) return 0;

  let intersectionSize = 0;
  for (const word of setA) {
    if (setB.has(word)) {
      intersectionSize++;
    }
  }

  const unionSize = new Set([...setA, ...setB]).size;
  return intersectionSize / unionSize;
}

/**
 * Mark an existing transaction as confirmed by a statement.
 * This is called when a statement is processed and a matching
 * alert-sourced transaction is found — the statement serves as
 * a second confirmation of the transaction's validity.
 */
export async function markStatementConfirmed(
  userId: string,
  transactionId: string
): Promise<void> {
  const db = admin.firestore();
  const txnDoc = db
    .collection('users')
    .doc(userId)
    .collection('transactions')
    .doc(transactionId);

  await txnDoc.update({
    statementConfirmed: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}
