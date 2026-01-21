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
Object.defineProperty(exports, "__esModule", { value: true });
exports.analyzeTravel = void 0;
const functions = __importStar(require("firebase-functions"));
const gmailService_1 = require("./services/gmailService");
const pdfService_1 = require("./services/pdfService");
const openaiService_1 = require("./services/openaiService");
const bookingDetector_1 = require("./utils/bookingDetector");
// OpenAI API Key from environment
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || functions.config().openai?.key;
exports.analyzeTravel = functions
    .runWith({
    timeoutSeconds: 540, // 9 minutes (max for HTTP functions)
    memory: '1GB',
})
    .https.onCall(async (data, context) => {
    // Validate request
    if (!data.accessToken) {
        throw new functions.https.HttpsError('invalid-argument', 'Access token is required');
    }
    if (!OPENAI_API_KEY) {
        throw new functions.https.HttpsError('failed-precondition', 'OpenAI API key not configured');
    }
    const options = {
        batchSize: data.options?.batchSize || 5,
        batch: data.options?.batch || 1,
        year: data.options?.year || new Date().getFullYear(),
    };
    console.log(`Processing batch ${options.batch} with size ${options.batchSize}`);
    // Initialize services
    const gmailService = new gmailService_1.GmailService(data.accessToken);
    const pdfService = new pdfService_1.PdfService();
    const openaiService = new openaiService_1.OpenAIService(OPENAI_API_KEY);
    try {
        // Fetch travel emails
        const { messages, moreBatches, totalEmails } = await gmailService.fetchTravelEmails(options);
        console.log(`Found ${messages.length} emails in this batch, ${totalEmails} total`);
        const travels = [];
        for (const message of messages) {
            console.log(`Processing: ${message.subject}`);
            // Detect booking type
            const bookingType = (0, bookingDetector_1.detectBookingType)(message.subject, message.from);
            console.log(`Detected type: ${bookingType}`);
            let content = '';
            let pdfParseStatus = 'not_attempted';
            let pdfParseError = '';
            // Try PDF attachments first
            if (message.pdfAttachments.length > 0) {
                pdfParseStatus = 'attempted';
                for (const pdf of message.pdfAttachments) {
                    try {
                        const pdfBuffer = await gmailService.fetchPdfAttachment(message.id, pdf.attachmentId);
                        content = await pdfService.extractText(pdfBuffer);
                        pdfParseStatus = 'success';
                        console.log(`Extracted ${content.length} chars from PDF`);
                        break; // Use first successful PDF
                    }
                    catch (error) {
                        pdfParseStatus = 'error';
                        pdfParseError = error.message;
                        console.error(`PDF parse error: ${error.message}`);
                    }
                }
            }
            // Fall back to email body if no PDF content
            if (!content && message.body && message.body.length > 100) {
                content = message.body;
                pdfParseStatus = 'email_body';
            }
            if (!content) {
                console.log('No content to analyze, skipping');
                continue;
            }
            // Extract booking data using OpenAI
            try {
                const bookingData = await openaiService.extractBookingData(content, bookingType);
                if (bookingData && Object.keys(bookingData).length > 0) {
                    // Extract amount and convert to INR
                    let amount;
                    let currency;
                    let amountINR;
                    if ('total_amount_paid' in bookingData && bookingData.total_amount_paid) {
                        amount = bookingData.total_amount_paid.amount ?? undefined;
                        currency = bookingData.total_amount_paid.currency ?? undefined;
                    }
                    else if ('total_amount' in bookingData && bookingData.total_amount) {
                        amount = bookingData.total_amount.amount ?? undefined;
                        currency = bookingData.total_amount.currency ?? undefined;
                    }
                    else if ('fees' in bookingData && bookingData.fees) {
                        amount = bookingData.fees.amount ?? undefined;
                        currency = bookingData.fees.currency ?? undefined;
                    }
                    if (amount && currency) {
                        amountINR = (0, openaiService_1.convertToINR)(amount, currency) ?? undefined;
                    }
                    // Extract origin/destination
                    let origin;
                    let destination;
                    if ('flights' in bookingData && bookingData.flights?.[0]) {
                        origin = bookingData.flights[0].departure?.city ?? undefined;
                        destination = bookingData.flights[0].arrival?.city ?? undefined;
                    }
                    else if ('departure' in bookingData && 'arrival' in bookingData) {
                        origin = bookingData.departure?.city || bookingData.departure?.location;
                        destination = bookingData.arrival?.city || bookingData.arrival?.location;
                    }
                    else if ('address' in bookingData) {
                        destination = bookingData.address?.city;
                    }
                    else if ('location' in bookingData) {
                        destination = bookingData.location?.city;
                    }
                    else if ('venue' in bookingData) {
                        destination = bookingData.venue?.city;
                    }
                    else if ('country' in bookingData) {
                        destination = bookingData.country;
                    }
                    travels.push({
                        ...bookingData,
                        booking_type: bookingType,
                        date: message.date,
                        pdfParseStatus,
                        pdfParseError,
                        origin,
                        destination,
                        amount,
                        currency,
                        amountINR,
                    });
                    console.log(`Successfully extracted ${bookingType} booking`);
                }
            }
            catch (error) {
                console.error(`OpenAI extraction error: ${error.message}`);
            }
        }
        // Sort by date
        travels.sort((a, b) => new Date(a.date || 0).getTime() - new Date(b.date || 0).getTime());
        console.log(`Returning ${travels.length} bookings`);
        return {
            travels,
            moreBatches,
            nextBatch: moreBatches ? options.batch + 1 : null,
            totalEmails,
        };
    }
    catch (error) {
        console.error('Travel analysis error:', error);
        throw new functions.https.HttpsError('internal', `Failed to analyze travel data: ${error.message}`);
    }
});
//# sourceMappingURL=index.js.map