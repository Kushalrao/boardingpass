"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AIChatService = void 0;
const sdk_1 = __importDefault(require("@anthropic-ai/sdk"));
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
// ============================================
// Indian Currency Formatting Helper
// ============================================
/**
 * Format a number in Indian currency style: Rs 1,23,456.78
 * Indian grouping: last 3 digits, then groups of 2
 */
function formatINR(amount) {
    const isNegative = amount < 0;
    const absAmount = Math.abs(amount);
    const parts = absAmount.toFixed(2).split('.');
    let intPart = parts[0];
    const decPart = parts[1];
    if (intPart.length > 3) {
        const last3 = intPart.slice(-3);
        const rest = intPart.slice(0, -3);
        const grouped = rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',');
        intPart = grouped + ',' + last3;
    }
    const sign = isNegative ? '-' : '';
    return `${sign}Rs ${intPart}${decPart !== '00' ? '.' + decPart : ''}`;
}
// ============================================
// JSON Parsing Helper
// ============================================
/**
 * Extract a JSON object from a string that may contain markdown
 * code blocks or surrounding text.
 */
function extractJson(raw) {
    const fenceMatch = raw.match(/```(?:json)?\s*\n?([\s\S]*?)\n?\s*```/);
    const cleaned = fenceMatch ? fenceMatch[1].trim() : raw.trim();
    try {
        return JSON.parse(cleaned);
    }
    catch {
        const objStart = cleaned.indexOf('{');
        const arrStart = cleaned.indexOf('[');
        let start;
        let openChar;
        let closeChar;
        if (objStart === -1 && arrStart === -1) {
            throw new Error('No JSON object or array found in response');
        }
        if (arrStart === -1 || (objStart !== -1 && objStart < arrStart)) {
            start = objStart;
            openChar = '{';
            closeChar = '}';
        }
        else {
            start = arrStart;
            openChar = '[';
            closeChar = ']';
        }
        let depth = 0;
        let inString = false;
        let escape = false;
        for (let i = start; i < cleaned.length; i++) {
            const ch = cleaned[i];
            if (escape) {
                escape = false;
                continue;
            }
            if (ch === '\\' && inString) {
                escape = true;
                continue;
            }
            if (ch === '"') {
                inString = !inString;
                continue;
            }
            if (inString)
                continue;
            if (ch === openChar)
                depth++;
            if (ch === closeChar)
                depth--;
            if (depth === 0) {
                return JSON.parse(cleaned.substring(start, i + 1));
            }
        }
        throw new Error('Could not find complete JSON in response');
    }
}
// ============================================
// Classification System Prompt
// ============================================
function getClassificationPrompt(currentDate) {
    return `You classify financial questions to determine what data is needed to answer them.
Today's date is ${currentDate}.

Given a user's question (and optionally conversation history for context), return a JSON object specifying what data to load from the database.

Available data types:
- monthly_aggregate: Pre-computed monthly spending/income summary with category and merchant breakdowns
- yearly_aggregate: Pre-computed yearly summary with monthly trends
- category_transactions: Specific transactions in one or more categories
- merchant_transactions: Transactions for a specific merchant
- account_transactions: Transactions for a specific bank account or credit card
- recent_transactions: The most recent N transactions
- recurring_patterns: Detected recurring payments (subscriptions, EMIs, etc.)
- specific_date_range: All transactions in a custom date range
- comparison: Two time periods to compare

Return ONLY valid JSON:
{
  "dataNeeded": ["monthly_aggregate"],
  "parameters": {
    "months": ["2026-03"],
    "categories": null,
    "merchants": null,
    "accountId": null,
    "dateRange": null,
    "limit": 10,
    "comparisonPeriods": null
  },
  "questionType": "aggregate_query"
}

Resolve relative references:
- "this month" = current month
- "last month" = previous month
- "this year" = current year
- Use conversation history to resolve "that", "it", "same period", etc.

Question types:
- aggregate_query: Questions about totals, averages, breakdowns (e.g., "How much did I spend this month?")
- transaction_list: Questions requesting specific transactions (e.g., "Show me my Swiggy orders")
- comparison: Questions comparing two time periods (e.g., "Did I spend more in Jan or Feb?")
- trend: Questions about changes over time (e.g., "How has my spending changed?")
- recommendation: Questions seeking financial advice (e.g., "Where can I cut spending?")
- general: Greetings, clarifications, or questions not needing financial data`;
}
// ============================================
// Answer Generation System Prompt
// ============================================
const ANSWER_SYSTEM_PROMPT = `You are a helpful personal finance assistant. Answer based ONLY on the provided financial data.
Be concise and specific. Use exact numbers from the data.
Format currency in Indian format: Rs 1,23,456.
If data is insufficient, say so honestly. Don't make up numbers.
Keep responses under 200 words unless detailed analysis is requested.
When comparing periods, use percentages and absolute differences.
For recommendations, be specific and actionable based on the data patterns.
Do not use markdown formatting like ** or ## - use plain text with natural emphasis.`;
// ============================================
// Session Timeout
// ============================================
const SESSION_TIMEOUT_MS = 30 * 60 * 1000; // 30 minutes
// ============================================
// AI Chat Service
// ============================================
class AIChatService {
    constructor(apiKey) {
        this.client = new sdk_1.default({ apiKey });
        this.db = admin.firestore();
    }
    // ------------------------------------------
    // Public: Main entry point
    // ------------------------------------------
    /**
     * Main entry point -- handles the full question-answer flow.
     *
     * 1. Get or create chat session
     * 2. Check rate limit (30/hour, 200/day)
     * 3. Get conversation history (last 10 messages)
     * 4. Call 1: Classify the question (Claude Haiku)
     * 5. Context Assembly: Load relevant data from Firestore
     * 6. Call 2: Generate answer (Claude Sonnet)
     * 7. Save messages to session
     * 8. Return answer + sessionId
     */
    async askQuestion(userId, question, sessionId) {
        // 1. Get or create chat session
        const session = await this.getOrCreateSession(userId, sessionId);
        // 2. Check rate limit
        await this.checkRateLimit(userId);
        // 3. Conversation history (last 10 messages)
        const conversationHistory = session.messages.slice(-10);
        // 4. Call 1: Classify the question
        const classification = await this.classifyQuestion(question, conversationHistory);
        // 5. Context Assembly: Load relevant data from Firestore
        const context = await this.assembleContext(userId, classification);
        // 6. Call 2: Generate answer
        const answer = await this.generateAnswer(question, context, conversationHistory);
        // 7. Save messages to session
        await this.saveMessages(userId, session.sessionId, question, answer);
        // 8. Return answer + sessionId
        return { answer, sessionId: session.sessionId };
    }
    // ------------------------------------------
    // Call 1: Classify the question
    // ------------------------------------------
    /**
     * Uses Claude Haiku (fast, cheap) to classify the user's question
     * and determine what financial data is needed to answer it.
     */
    async classifyQuestion(question, conversationHistory) {
        const now = new Date();
        const currentDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
        // Build conversation context string for reference resolution
        let historyContext = '';
        if (conversationHistory.length > 0) {
            const recentMessages = conversationHistory.slice(-6);
            historyContext = '\n\nRecent conversation for context:\n';
            for (const msg of recentMessages) {
                historyContext += `${msg.role === 'user' ? 'User' : 'Assistant'}: ${msg.content}\n`;
            }
        }
        const response = await this.client.messages.create({
            model: 'claude-haiku-4-5-20251001',
            max_tokens: 500,
            temperature: 0,
            system: getClassificationPrompt(currentDate),
            messages: [
                {
                    role: 'user',
                    content: `${historyContext}\n\nUser's question: ${question}`,
                },
            ],
        });
        const textBlock = response.content.find((block) => block.type === 'text');
        if (!textBlock || textBlock.type !== 'text') {
            throw new functions.https.HttpsError('internal', 'Failed to classify question: no response from AI');
        }
        try {
            const parsed = extractJson(textBlock.text);
            // Validate required fields with sensible defaults
            if (!parsed.dataNeeded || !Array.isArray(parsed.dataNeeded)) {
                parsed.dataNeeded = [];
            }
            if (!parsed.parameters) {
                parsed.parameters = {};
            }
            if (!parsed.questionType) {
                parsed.questionType = 'general';
            }
            return parsed;
        }
        catch (error) {
            console.error('Failed to parse classification JSON:', textBlock.text, error);
            // Return a safe default that will fetch recent transactions
            return {
                dataNeeded: ['recent_transactions'],
                parameters: { limit: 10 },
                questionType: 'general',
            };
        }
    }
    // ------------------------------------------
    // Context Assembly
    // ------------------------------------------
    /**
     * Load relevant financial data from Firestore based on the
     * classification output, then format it as a readable string
     * for the answer-generation call.
     */
    async assembleContext(userId, classification) {
        const basePath = `users/${userId}`;
        const contextParts = [];
        for (const need of classification.dataNeeded) {
            switch (need) {
                case 'monthly_aggregate': {
                    const months = classification.parameters.months || [this.getCurrentMonth()];
                    for (const month of months) {
                        const docId = `monthly_${month.replace('-', '_')}`;
                        const snap = await this.db
                            .doc(`${basePath}/financialAggregates/${docId}`)
                            .get();
                        if (snap.exists) {
                            contextParts.push(this.formatMonthlyAggregate(snap.data(), month));
                        }
                        else {
                            contextParts.push(`No data available for ${month}.`);
                        }
                    }
                    break;
                }
                case 'yearly_aggregate': {
                    const months = classification.parameters.months || [this.getCurrentMonth()];
                    // Extract year from the first month parameter, or use current year
                    const year = months.length > 0 ? months[0].substring(0, 4) : String(new Date().getFullYear());
                    const docId = `yearly_${year}`;
                    const snap = await this.db
                        .doc(`${basePath}/financialAggregates/${docId}`)
                        .get();
                    if (snap.exists) {
                        contextParts.push(this.formatYearlyAggregate(snap.data(), year));
                    }
                    else {
                        contextParts.push(`No yearly data available for ${year}.`);
                    }
                    break;
                }
                case 'category_transactions': {
                    const categories = classification.parameters.categories || [];
                    const limit = classification.parameters.limit || 20;
                    const dateRange = classification.parameters.dateRange;
                    let query = this.db
                        .collection(`${basePath}/transactions`)
                        .where('category', 'in', categories.length > 0 ? categories : ['other'])
                        .orderBy('date', 'desc')
                        .limit(limit);
                    if (dateRange) {
                        query = this.db
                            .collection(`${basePath}/transactions`)
                            .where('category', 'in', categories.length > 0 ? categories : ['other'])
                            .where('date', '>=', admin.firestore.Timestamp.fromDate(new Date(dateRange.from)))
                            .where('date', '<=', admin.firestore.Timestamp.fromDate(new Date(dateRange.to + 'T23:59:59')))
                            .orderBy('date', 'desc')
                            .limit(limit);
                    }
                    const snap = await query.get();
                    const transactions = snap.docs.map((doc) => doc.data());
                    const label = `Transactions in ${categories.join(', ')}`;
                    contextParts.push(this.formatTransactions(transactions, label));
                    break;
                }
                case 'merchant_transactions': {
                    const merchants = classification.parameters.merchants || [];
                    const limit = classification.parameters.limit || 20;
                    if (merchants.length > 0) {
                        // Firestore 'in' queries support up to 30 values
                        const snap = await this.db
                            .collection(`${basePath}/transactions`)
                            .where('merchant', 'in', merchants.slice(0, 30))
                            .orderBy('date', 'desc')
                            .limit(limit)
                            .get();
                        const transactions = snap.docs.map((doc) => doc.data());
                        const label = `Transactions for ${merchants.join(', ')}`;
                        contextParts.push(this.formatTransactions(transactions, label));
                    }
                    break;
                }
                case 'account_transactions': {
                    const accountId = classification.parameters.accountId;
                    const limit = classification.parameters.limit || 20;
                    if (accountId) {
                        const snap = await this.db
                            .collection(`${basePath}/transactions`)
                            .where('accountId', '==', accountId)
                            .orderBy('date', 'desc')
                            .limit(limit)
                            .get();
                        const transactions = snap.docs.map((doc) => doc.data());
                        const label = `Transactions for account ${accountId}`;
                        contextParts.push(this.formatTransactions(transactions, label));
                    }
                    break;
                }
                case 'recent_transactions': {
                    const limit = classification.parameters.limit || 10;
                    const snap = await this.db
                        .collection(`${basePath}/transactions`)
                        .orderBy('date', 'desc')
                        .limit(limit)
                        .get();
                    const transactions = snap.docs.map((doc) => doc.data());
                    contextParts.push(this.formatTransactions(transactions, 'Recent Transactions'));
                    break;
                }
                case 'recurring_patterns': {
                    const snap = await this.db
                        .doc(`${basePath}/financialAggregates/recurring`)
                        .get();
                    if (snap.exists) {
                        const data = snap.data();
                        contextParts.push(this.formatRecurringPatterns(data));
                    }
                    else {
                        contextParts.push('No recurring payment patterns detected yet.');
                    }
                    break;
                }
                case 'specific_date_range': {
                    const dateRange = classification.parameters.dateRange;
                    const limit = classification.parameters.limit || 50;
                    if (dateRange) {
                        const snap = await this.db
                            .collection(`${basePath}/transactions`)
                            .where('date', '>=', admin.firestore.Timestamp.fromDate(new Date(dateRange.from)))
                            .where('date', '<=', admin.firestore.Timestamp.fromDate(new Date(dateRange.to + 'T23:59:59')))
                            .orderBy('date', 'desc')
                            .limit(limit)
                            .get();
                        const transactions = snap.docs.map((doc) => doc.data());
                        const label = `Transactions from ${dateRange.from} to ${dateRange.to}`;
                        contextParts.push(this.formatTransactions(transactions, label));
                    }
                    break;
                }
                case 'comparison': {
                    const periods = classification.parameters.comparisonPeriods;
                    if (periods) {
                        // Try monthly aggregates first
                        for (const period of [periods.period1, periods.period2]) {
                            // Determine if it's a month (YYYY-MM) or year (YYYY) format
                            if (period.length === 7) {
                                // Monthly: YYYY-MM
                                const docId = `monthly_${period.replace('-', '_')}`;
                                const snap = await this.db
                                    .doc(`${basePath}/financialAggregates/${docId}`)
                                    .get();
                                if (snap.exists) {
                                    contextParts.push(this.formatMonthlyAggregate(snap.data(), period));
                                }
                                else {
                                    contextParts.push(`No data available for ${period}.`);
                                }
                            }
                            else if (period.length === 4) {
                                // Yearly: YYYY
                                const docId = `yearly_${period}`;
                                const snap = await this.db
                                    .doc(`${basePath}/financialAggregates/${docId}`)
                                    .get();
                                if (snap.exists) {
                                    contextParts.push(this.formatYearlyAggregate(snap.data(), period));
                                }
                                else {
                                    contextParts.push(`No data available for ${period}.`);
                                }
                            }
                        }
                    }
                    break;
                }
                default:
                    break;
            }
        }
        if (contextParts.length === 0) {
            return 'No specific financial data was loaded. The user may be asking a general question or greeting.';
        }
        return contextParts.join('\n\n---\n\n');
    }
    // ------------------------------------------
    // Call 2: Generate the answer
    // ------------------------------------------
    /**
     * Uses Claude Sonnet (better reasoning) to generate a helpful
     * financial answer based on the assembled context data.
     */
    async generateAnswer(question, context, conversationHistory) {
        // Build conversation messages for continuity (last 5)
        const recentHistory = conversationHistory.slice(-5);
        const messages = [];
        for (const msg of recentHistory) {
            messages.push({
                role: msg.role,
                content: msg.content,
            });
        }
        // Add the current question with the assembled context
        messages.push({
            role: 'user',
            content: `Here is the relevant financial data to answer my question:\n\n${context}\n\nMy question: ${question}`,
        });
        const response = await this.client.messages.create({
            model: 'claude-sonnet-4-5-20250929',
            max_tokens: 800,
            temperature: 0.3,
            system: ANSWER_SYSTEM_PROMPT,
            messages,
        });
        const textBlock = response.content.find((block) => block.type === 'text');
        if (!textBlock || textBlock.type !== 'text') {
            throw new functions.https.HttpsError('internal', 'Failed to generate answer: no response from AI');
        }
        return textBlock.text;
    }
    // ------------------------------------------
    // Rate Limiting
    // ------------------------------------------
    /**
     * Enforce rate limits: 30 questions per hour, 200 per day.
     * Stores counters at users/{userId}/rateLimits/aiChat.
     */
    async checkRateLimit(userId) {
        const rateLimitRef = this.db.doc(`users/${userId}/rateLimits/aiChat`);
        const now = Date.now();
        await this.db.runTransaction(async (txn) => {
            const snap = await txn.get(rateLimitRef);
            const data = snap.exists ? snap.data() : {};
            let hourlyCount = data.hourlyCount || 0;
            let hourlyResetAt = data.hourlyResetAt || 0;
            let dailyCount = data.dailyCount || 0;
            let dailyResetAt = data.dailyResetAt || 0;
            // Reset hourly counter if the window has elapsed
            if (now >= hourlyResetAt) {
                hourlyCount = 0;
                hourlyResetAt = now + 60 * 60 * 1000; // 1 hour from now
            }
            // Reset daily counter if the window has elapsed
            if (now >= dailyResetAt) {
                dailyCount = 0;
                // Reset at midnight: compute ms until next midnight
                const tomorrow = new Date();
                tomorrow.setHours(24, 0, 0, 0);
                dailyResetAt = tomorrow.getTime();
            }
            // Check limits
            if (hourlyCount >= 30) {
                const minutesLeft = Math.ceil((hourlyResetAt - now) / 60000);
                throw new functions.https.HttpsError('resource-exhausted', `You've reached the limit of 30 questions per hour. Please try again in ${minutesLeft} minute${minutesLeft === 1 ? '' : 's'}.`);
            }
            if (dailyCount >= 200) {
                throw new functions.https.HttpsError('resource-exhausted', 'You\'ve reached the limit of 200 questions per day. Please try again tomorrow.');
            }
            // Increment counters
            txn.set(rateLimitRef, {
                hourlyCount: hourlyCount + 1,
                hourlyResetAt,
                dailyCount: dailyCount + 1,
                dailyResetAt,
            });
        });
    }
    // ------------------------------------------
    // Session Management
    // ------------------------------------------
    /**
     * Get or create a chat session.
     * If a sessionId is provided, load it (unless it has expired).
     * Sessions expire after 30 minutes of inactivity.
     */
    async getOrCreateSession(userId, sessionId) {
        const sessionsPath = `users/${userId}/chatSessions`;
        if (sessionId) {
            const sessionRef = this.db.doc(`${sessionsPath}/${sessionId}`);
            const snap = await sessionRef.get();
            if (snap.exists) {
                const session = snap.data();
                const lastMessageTime = session.lastMessageAt.toMillis();
                const now = Date.now();
                // If session is still active (within 30 minutes), reuse it
                if (now - lastMessageTime < SESSION_TIMEOUT_MS) {
                    return {
                        sessionId,
                        messages: session.messages || [],
                    };
                }
                // Session expired; fall through to create a new one
            }
            // Session not found or expired; fall through to create a new one
        }
        // Create a new session
        const newSessionRef = this.db.collection(sessionsPath).doc();
        const now = admin.firestore.Timestamp.now();
        const newSession = {
            createdAt: now,
            lastMessageAt: now,
            title: '',
            messages: [],
        };
        await newSessionRef.set(newSession);
        return {
            sessionId: newSessionRef.id,
            messages: [],
        };
    }
    /**
     * Save user question and AI answer to the chat session.
     * Also auto-generates a title from the first question if not set.
     */
    async saveMessages(userId, sessionId, question, answer) {
        const sessionRef = this.db.doc(`users/${userId}/chatSessions/${sessionId}`);
        const now = admin.firestore.Timestamp.now();
        const userMessage = {
            role: 'user',
            content: question,
            timestamp: now,
        };
        const assistantMessage = {
            role: 'assistant',
            content: answer,
            timestamp: now,
        };
        const snap = await sessionRef.get();
        const session = snap.exists ? snap.data() : null;
        const updateData = {
            messages: admin.firestore.FieldValue.arrayUnion(userMessage, assistantMessage),
            lastMessageAt: now,
        };
        // Auto-generate title from first question if not already set
        if (!session?.title) {
            // Truncate to a reasonable title length
            const title = question.length > 60 ? question.substring(0, 57) + '...' : question;
            updateData.title = title;
        }
        await sessionRef.update(updateData);
    }
    // ------------------------------------------
    // Formatting Helpers
    // ------------------------------------------
    /**
     * Format a MonthlyAggregate document into a readable context string.
     */
    formatMonthlyAggregate(data, period) {
        const agg = data;
        const lines = [];
        // Human-readable month label
        const monthLabel = this.formatMonthLabel(period);
        lines.push(`Monthly Summary for ${monthLabel}:`);
        lines.push(`Total Spending: ${formatINR(agg.totalSpending)}`);
        lines.push(`Total Income: ${formatINR(agg.totalIncome)}`);
        const netSign = agg.netFlow >= 0 ? '+' : '';
        lines.push(`Net Flow: ${netSign}${formatINR(agg.netFlow)}`);
        lines.push(`Transaction Count: ${agg.transactionCount}`);
        // Category breakdown
        if (agg.categoryBreakdown && Object.keys(agg.categoryBreakdown).length > 0) {
            lines.push('');
            lines.push('Category Breakdown:');
            const sorted = Object.entries(agg.categoryBreakdown)
                .sort(([, a], [, b]) => b.total - a.total);
            let rank = 1;
            for (const [category, info] of sorted) {
                lines.push(`  ${rank}. ${this.capitalizeCategory(category)}: ${formatINR(info.total)} (${info.count} transaction${info.count === 1 ? '' : 's'}, avg ${formatINR(info.avgTransaction)})`);
                rank++;
            }
        }
        // Merchant breakdown (top 10)
        if (agg.merchantBreakdown && Object.keys(agg.merchantBreakdown).length > 0) {
            lines.push('');
            lines.push('Top Merchants:');
            const sorted = Object.entries(agg.merchantBreakdown)
                .sort(([, a], [, b]) => b.total - a.total)
                .slice(0, 10);
            let rank = 1;
            for (const [merchant, info] of sorted) {
                lines.push(`  ${rank}. ${merchant}: ${formatINR(info.total)} (${info.count} transaction${info.count === 1 ? '' : 's'})`);
                rank++;
            }
        }
        // Largest and smallest transactions
        if (agg.largestTransaction) {
            lines.push('');
            lines.push(`Largest Transaction: ${formatINR(agg.largestTransaction.amount)} at ${agg.largestTransaction.merchant} on ${agg.largestTransaction.date}`);
        }
        if (agg.smallestTransaction) {
            lines.push(`Smallest Transaction: ${formatINR(agg.smallestTransaction.amount)} at ${agg.smallestTransaction.merchant} on ${agg.smallestTransaction.date}`);
        }
        return lines.join('\n');
    }
    /**
     * Format a YearlyAggregate document into a readable context string.
     */
    formatYearlyAggregate(data, year) {
        const agg = data;
        const lines = [];
        lines.push(`Yearly Summary for ${year}:`);
        lines.push(`Total Spending: ${formatINR(agg.totalSpending)}`);
        lines.push(`Total Income: ${formatINR(agg.totalIncome)}`);
        const netSign = agg.netFlow >= 0 ? '+' : '';
        lines.push(`Net Flow: ${netSign}${formatINR(agg.netFlow)}`);
        lines.push(`Transaction Count: ${agg.transactionCount}`);
        // Category breakdown
        if (agg.categoryBreakdown && Object.keys(agg.categoryBreakdown).length > 0) {
            lines.push('');
            lines.push('Category Breakdown:');
            const sorted = Object.entries(agg.categoryBreakdown)
                .sort(([, a], [, b]) => b.total - a.total);
            let rank = 1;
            for (const [category, info] of sorted) {
                lines.push(`  ${rank}. ${this.capitalizeCategory(category)}: ${formatINR(info.total)} (${info.count} transaction${info.count === 1 ? '' : 's'})`);
                rank++;
            }
        }
        // Monthly trend
        if (agg.monthlyTrend && agg.monthlyTrend.length > 0) {
            lines.push('');
            lines.push('Monthly Trend:');
            for (const entry of agg.monthlyTrend) {
                lines.push(`  ${this.formatMonthLabel(entry.month)}: Spending ${formatINR(entry.spending)}, Income ${formatINR(entry.income)}`);
            }
        }
        return lines.join('\n');
    }
    /**
     * Format a list of Transaction documents into a readable context string.
     */
    formatTransactions(transactions, label) {
        if (transactions.length === 0) {
            return `${label}: No transactions found.`;
        }
        const lines = [];
        lines.push(`${label} (${transactions.length} transaction${transactions.length === 1 ? '' : 's'}):`);
        let rank = 1;
        for (const txn of transactions) {
            const dateStr = this.formatTransactionDate(txn.date);
            const typeIndicator = txn.type === 'credit' ? '+' : '-';
            const accountLabel = txn.accountId || '';
            lines.push(`  ${rank}. ${dateStr} - ${txn.merchant} - ${typeIndicator}${formatINR(txn.amount)} (${this.capitalizeCategory(txn.category)})${accountLabel ? ' - ' + accountLabel : ''}`);
            rank++;
        }
        return lines.join('\n');
    }
    /**
     * Format recurring payment patterns into a readable context string.
     */
    formatRecurringPatterns(data) {
        if (!data.patterns || data.patterns.length === 0) {
            return 'No recurring payment patterns detected.';
        }
        const lines = [];
        lines.push(`Recurring Payments (${data.patterns.length} detected):`);
        let rank = 1;
        for (const pattern of data.patterns) {
            lines.push(`  ${rank}. ${pattern.merchant}: ${formatINR(pattern.amount)} (${pattern.frequency}) - Category: ${this.capitalizeCategory(pattern.category)}, Next expected: ${pattern.nextExpected}`);
            rank++;
        }
        return lines.join('\n');
    }
    // ------------------------------------------
    // Utility Helpers
    // ------------------------------------------
    /**
     * Get current month in YYYY-MM format.
     */
    getCurrentMonth() {
        const now = new Date();
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    }
    /**
     * Convert a YYYY-MM period string to a human-readable label.
     * e.g., "2026-03" => "March 2026"
     */
    formatMonthLabel(period) {
        const monthNames = [
            'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December',
        ];
        const parts = period.split('-');
        if (parts.length < 2)
            return period;
        const monthIndex = parseInt(parts[1], 10) - 1;
        if (monthIndex < 0 || monthIndex > 11)
            return period;
        return `${monthNames[monthIndex]} ${parts[0]}`;
    }
    /**
     * Format a Firestore Timestamp to a short date string: "Mar 5".
     */
    formatTransactionDate(date) {
        const shortMonths = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        const d = date.toDate();
        return `${shortMonths[d.getMonth()]} ${d.getDate()}`;
    }
    /**
     * Capitalize a category slug for display.
     * e.g., "food" => "Food", "emi" => "EMI", "health" => "Health"
     */
    capitalizeCategory(category) {
        const specialCases = {
            emi: 'EMI',
            upi: 'UPI',
        };
        if (specialCases[category])
            return specialCases[category];
        return category
            .split('_')
            .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
            .join(' ');
    }
}
exports.AIChatService = AIChatService;
//# sourceMappingURL=aiChatService.js.map