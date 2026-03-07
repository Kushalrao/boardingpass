"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.FinanceExtractionService = void 0;
const sdk_1 = __importDefault(require("@anthropic-ai/sdk"));
// ============================================
// System Prompts
// ============================================
const TRANSACTION_SYSTEM_PROMPT = `You extract financial transaction data from Indian bank/financial notification emails.
Return ONLY a valid JSON object. No text outside JSON.

SECURITY RULES:
- NEVER include full account numbers. Use only last 4 digits prefixed with "XX" (e.g., "XX1234")
- NEVER include full card numbers. Use only last 4 digits.
- If the email is an OTP, verification code, or not about a financial transaction, return: {"skip": true}

Return this JSON schema:
{
  "skip": false,
  "type": "debit" or "credit",
  "amount": <number>,
  "currency": "INR",
  "amountINR": <number>,
  "accountMasked": "XX1234",
  "accountType": "bank_account" | "credit_card" | "upi" | "wallet",
  "provider": "<bank/app name>",
  "merchant": "<normalized merchant name>",
  "merchantRaw": "<exactly as in email>",
  "category": "<one of: food, transport, shopping, utilities, entertainment, health, education, travel, groceries, fuel, investment, salary, emi, transfer, rent, insurance, other>",
  "transactionDate": "YYYY-MM-DD",
  "transactionTime": "HH:mm" or null,
  "referenceNumber": "<string or null>",
  "balance": <number or null>,
  "status": "confirmed" | "pending" | "failed"
}`;
const STATEMENT_SYSTEM_PROMPT = `You extract financial transaction data from Indian bank/credit card statement text.
Return ONLY a valid JSON object. No text outside JSON.

SECURITY RULES:
- NEVER include full account numbers. Use only last 4 digits prefixed with "XX" (e.g., "XX1234")
- NEVER include full card numbers. Use only last 4 digits.

Return this JSON schema:
{
  "transactions": [
    {
      "skip": false,
      "type": "debit" or "credit",
      "amount": <number>,
      "currency": "INR",
      "amountINR": <number>,
      "accountMasked": "XX1234",
      "accountType": "bank_account" | "credit_card" | "upi" | "wallet",
      "provider": "<bank/app name>",
      "merchant": "<normalized merchant name>",
      "merchantRaw": "<exactly as in statement>",
      "category": "<one of: food, transport, shopping, utilities, entertainment, health, education, travel, groceries, fuel, investment, salary, emi, transfer, rent, insurance, other>",
      "transactionDate": "YYYY-MM-DD",
      "transactionTime": "HH:mm" or null,
      "referenceNumber": "<string or null>",
      "balance": <number or null>,
      "status": "confirmed"
    }
  ],
  "statementPeriod": { "from": "YYYY-MM-DD", "to": "YYYY-MM-DD" },
  "accountMasked": "XX1234",
  "provider": "<bank/issuer name>",
  "totalDue": <number or null>,
  "minimumDue": <number or null>,
  "dueDate": "YYYY-MM-DD" or null
}

Extract ALL transactions listed in the statement. For credit card statements, debits are purchases and credits are payments/refunds.`;
// ============================================
// JSON Parsing Helper
// ============================================
/**
 * Extract a JSON object or array from a string that may contain
 * markdown code blocks or surrounding text.
 */
function extractJson(raw) {
    // Strip markdown code fences if present: ```json ... ``` or ``` ... ```
    const fenceMatch = raw.match(/```(?:json)?\s*\n?([\s\S]*?)\n?\s*```/);
    const cleaned = fenceMatch ? fenceMatch[1].trim() : raw.trim();
    // Try parsing directly
    try {
        return JSON.parse(cleaned);
    }
    catch {
        // Fall back: find the first { or [ and its matching closing brace/bracket
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
        // Walk forward counting braces to find the matching close
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
// Finance Extraction Service
// ============================================
class FinanceExtractionService {
    constructor(apiKey) {
        this.client = new sdk_1.default({ apiKey });
    }
    /**
     * Extract transaction data from a short alert email.
     * Uses Claude Haiku for speed and cost efficiency.
     */
    async extractTransaction(content, emailType) {
        try {
            const response = await this.client.messages.create({
                model: 'claude-haiku-4-5-20251001',
                max_tokens: 1000,
                temperature: 0,
                system: TRANSACTION_SYSTEM_PROMPT,
                messages: [
                    {
                        role: 'user',
                        content: `Email type hint: ${emailType}\n\nEmail content:\n${content}`,
                    },
                ],
            });
            // Extract text from response
            const textBlock = response.content.find((block) => block.type === 'text');
            if (!textBlock || textBlock.type !== 'text') {
                console.error('No text block in Claude response');
                return null;
            }
            const parsed = extractJson(textBlock.text);
            // If Claude determined this is not a transaction, return null
            if (parsed.skip === true) {
                return null;
            }
            return parsed;
        }
        catch (error) {
            console.error('Error extracting transaction:', error);
            return null;
        }
    }
    /**
     * Extract multiple transactions from a statement PDF text.
     * Uses Claude Sonnet for better accuracy on complex documents.
     */
    async extractStatement(content) {
        try {
            const response = await this.client.messages.create({
                model: 'claude-sonnet-4-5-20250929',
                max_tokens: 4000,
                temperature: 0,
                system: STATEMENT_SYSTEM_PROMPT,
                messages: [
                    {
                        role: 'user',
                        content: `Statement text:\n${content}`,
                    },
                ],
            });
            // Extract text from response
            const textBlock = response.content.find((block) => block.type === 'text');
            if (!textBlock || textBlock.type !== 'text') {
                console.error('No text block in Claude response for statement');
                return null;
            }
            const parsed = extractJson(textBlock.text);
            // Basic validation: must have transactions array
            if (!parsed.transactions || !Array.isArray(parsed.transactions)) {
                console.error('Statement extraction missing transactions array');
                return null;
            }
            // Filter out any skip entries from the transactions list
            parsed.transactions = parsed.transactions.filter((txn) => txn.skip !== true);
            return parsed;
        }
        catch (error) {
            console.error('Error extracting statement:', error);
            return null;
        }
    }
    /**
     * Extract transactions from a PDF buffer by sending it directly to Claude
     * as a document. This preserves table structure, handles scanned PDFs,
     * and produces far better results than text extraction.
     *
     * Uses Claude Sonnet for accuracy on complex bank/CC statement layouts.
     *
     * @param pdfBuffer - Decrypted PDF buffer (must not be password-protected)
     */
    async extractFromPdf(pdfBuffer) {
        try {
            const pdfBase64 = pdfBuffer.toString('base64');
            const response = await this.client.messages.create({
                model: 'claude-sonnet-4-5-20250929',
                max_tokens: 8000,
                temperature: 0,
                system: STATEMENT_SYSTEM_PROMPT,
                messages: [
                    {
                        role: 'user',
                        content: [
                            {
                                type: 'document',
                                source: {
                                    type: 'base64',
                                    media_type: 'application/pdf',
                                    data: pdfBase64,
                                },
                            },
                            {
                                type: 'text',
                                text: 'Extract ALL transactions from this bank/credit card statement PDF. Return the JSON as specified in the system prompt.',
                            },
                        ],
                    },
                ],
            });
            const textBlock = response.content.find((block) => block.type === 'text');
            if (!textBlock || textBlock.type !== 'text') {
                console.error('No text block in Claude response for PDF extraction');
                return null;
            }
            const parsed = extractJson(textBlock.text);
            if (!parsed.transactions || !Array.isArray(parsed.transactions)) {
                console.error('PDF extraction missing transactions array');
                return null;
            }
            parsed.transactions = parsed.transactions.filter((txn) => txn.skip !== true);
            console.log(`extractFromPdf: Got ${parsed.transactions.length} transactions from PDF`);
            return parsed;
        }
        catch (error) {
            console.error('Error extracting from PDF:', error);
            return null;
        }
    }
}
exports.FinanceExtractionService = FinanceExtractionService;
//# sourceMappingURL=financeExtractionService.js.map