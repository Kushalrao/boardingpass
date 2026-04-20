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
exports.scanFlightEmails = exports.gmailWebhook = exports.setupGmailWatch = exports.storeRefreshToken = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const googleapis_1 = require("googleapis");
const gmailService_1 = require("./services/gmailService");
const gmailWatchService_1 = require("./services/gmailWatchService");
const flightDetector_1 = require("./services/flightDetector");
// Initialize Firebase Admin
if (!admin.apps.length) {
    admin.initializeApp();
}
// Environment variables
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
// ============================================
// HELPER: Store a detected flight email
// ============================================
async function storeDetectedFlightEmail(userId, message, detection, source) {
    const db = admin.firestore();
    // Truncate body to 10000 chars to avoid bloating Firestore documents
    const truncatedBody = message.body.length > 10000
        ? message.body.substring(0, 10000)
        : message.body;
    await db
        .collection('users')
        .doc(userId)
        .collection('detectedFlightEmails')
        .doc(message.id)
        .set({
        gmailMessageId: message.id,
        subject: message.subject,
        from: message.from,
        date: message.date,
        body: truncatedBody,
        hasPdfAttachments: message.pdfAttachments.length > 0,
        pdfAttachmentCount: message.pdfAttachments.length,
        detectionScore: detection.score,
        detectionConfidence: detection.confidence,
        matchedSignals: detection.matchedSignals,
        senderCategory: detection.senderCategory,
        senderDomain: detection.senderDomain,
        source,
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
        processed: false,
        extractedFlightData: null,
    });
}
// ============================================
// AUTH & GMAIL SETUP FUNCTIONS
// ============================================
/**
 * Store refresh token for Gmail access
 * Exchanges auth code for refresh token and stores it in Firestore
 */
exports.storeRefreshToken = functions
    .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
})
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const { authCode } = data;
    if (!authCode) {
        throw new functions.https.HttpsError('invalid-argument', 'Auth code is required');
    }
    if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
        throw new functions.https.HttpsError('failed-precondition', 'Google OAuth credentials not configured');
    }
    const userId = context.auth.uid;
    console.log(`Storing refresh token for user: ${userId}`);
    try {
        const oauth2Client = new googleapis_1.google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, 'postmessage');
        const { tokens } = await oauth2Client.getToken(authCode);
        if (!tokens.refresh_token) {
            throw new functions.https.HttpsError('failed-precondition', 'No refresh token returned. User may need to revoke app access and re-authorize.');
        }
        const db = admin.firestore();
        await db.collection('users').doc(userId).update({
            gmailRefreshToken: tokens.refresh_token,
            gmailTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { success: true };
    }
    catch (error) {
        console.error('Error storing refresh token:', error);
        throw new functions.https.HttpsError('internal', `Failed to store refresh token: ${error.message}`);
    }
});
/**
 * Set up Gmail watch for push notifications
 */
exports.setupGmailWatch = functions
    .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
})
    .https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const userId = context.auth.uid;
    console.log(`Setting up Gmail watch for user: ${userId}`);
    try {
        const watchService = new gmailWatchService_1.GmailWatchService();
        const { historyId, expiration } = await watchService.setupWatch(userId);
        return { success: true, historyId, expiration };
    }
    catch (error) {
        console.error('Error setting up Gmail watch:', error);
        throw new functions.https.HttpsError('internal', `Failed to set up Gmail watch: ${error.message}`);
    }
});
// ============================================
// GMAIL WEBHOOK — Real-time Pub/Sub Processing
// ============================================
/**
 * Triggered by Gmail push notifications via Pub/Sub.
 *
 * When a new email arrives in a watched Gmail inbox, Google publishes
 * a message to our Pub/Sub topic. This function:
 *  1. Decodes the notification to get the user's email and historyId
 *  2. Finds the corresponding user in Firestore
 *  3. Fetches new message IDs since the last known historyId
 *  4. Runs flight detection on each email
 *  5. Stores detected flight emails in Firestore
 *  6. Updates the stored historyId for the next notification
 */
exports.gmailWebhook = functions
    .runWith({
    timeoutSeconds: 120,
    memory: '256MB',
})
    .pubsub.topic('gmail-notifications')
    .onPublish(async (pubsubMessage) => {
    // Decode the Pub/Sub message
    let emailAddress;
    let historyId;
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
        console.log(`gmailWebhook: notification for ${emailAddress}, historyId=${historyId}`);
    }
    catch (err) {
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
    try {
        const watchService = new gmailWatchService_1.GmailWatchService();
        // Get new message IDs since last history checkpoint
        const newMessageIds = await watchService.getNewMessages(userId, lastHistoryId);
        console.log(`gmailWebhook: ${newMessageIds.length} new messages for user ${userId}`);
        if (newMessageIds.length === 0) {
            // Update historyId even if no new messages
            await db.collection('users').doc(userId).update({
                gmailWatchHistoryId: historyId,
            });
            return;
        }
        // Get a fresh access token for fetching email content
        const accessToken = await watchService.getAccessToken(userId);
        const gmailService = new gmailService_1.GmailService(accessToken);
        // Fetch and analyze each new email
        for (const messageId of newMessageIds) {
            try {
                const message = await gmailService.fetchMessageById(messageId);
                if (!message) {
                    console.warn(`gmailWebhook: Could not fetch message ${messageId}`);
                    continue;
                }
                // Run flight detection
                const detection = (0, flightDetector_1.detectFlightEmail)(message);
                if (detection.isFlightEmail) {
                    console.log(`gmailWebhook: FLIGHT DETECTED [${detection.confidence}] score=${detection.score} ` +
                        `signals=[${detection.matchedSignals.join(', ')}] subject="${message.subject}"`);
                    await storeDetectedFlightEmail(userId, message, detection, 'webhook');
                }
            }
            catch (err) {
                console.error(`gmailWebhook: Error processing message ${messageId}:`, err);
                continue;
            }
        }
        // Update the historyId to the latest value
        await db.collection('users').doc(userId).update({
            gmailWatchHistoryId: historyId,
        });
        console.log(`gmailWebhook: Finished processing for user ${userId}`);
    }
    catch (error) {
        console.error(`gmailWebhook: Error for user ${userId}:`, error);
        // Still try to update historyId so we don't replay on next notification
        try {
            await db.collection('users').doc(userId).update({
                gmailWatchHistoryId: historyId,
            });
        }
        catch (_updateErr) {
            console.error('gmailWebhook: Failed to update historyId after error');
        }
    }
});
// ============================================
// SCAN FLIGHT EMAILS — Batch Historical Scan
// ============================================
/**
 * Scans the user's Gmail history for flight booking emails.
 * Uses a Gmail search query to pre-filter, then runs the scorer
 * on each result for precise detection.
 *
 * Called from the Flutter app to backfill past flight emails.
 * Processes in batches — call repeatedly with incrementing batch number.
 */
exports.scanFlightEmails = functions
    .runWith({
    timeoutSeconds: 300,
    memory: '512MB',
})
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const userId = context.auth.uid;
    const batch = data?.batch || 1;
    const batchSize = Math.min(data?.batchSize || 20, 50);
    console.log(`scanFlightEmails: user=${userId}, batch=${batch}, batchSize=${batchSize}`);
    try {
        // Use provided access token (web) or get one from refresh token (mobile)
        let accessToken;
        if (data?.accessToken) {
            accessToken = data.accessToken;
        }
        else {
            const watchService = new gmailWatchService_1.GmailWatchService();
            accessToken = await watchService.getAccessToken(userId);
        }
        const gmailService = new gmailService_1.GmailService(accessToken);
        // Gmail search query — broad first pass, scorer does precise filtering
        const query = [
            'from:(goindigo.in OR airindia.com OR airindia.in OR spicejet.com OR airvistara.com OR airasia.com OR akasaair.com OR allianceair.in OR starair.in OR flybigair.com',
            'OR emirates.com OR qatarairways.com OR etihad.com OR flydubai.com OR omanair.com OR saudia.com OR gulfair.com',
            'OR singaporeair.com OR malaysiaairlines.com OR thaiairways.com OR cathaypacific.com OR srilankan.com',
            'OR lufthansa.com OR britishairways.com OR klm.com OR airfrance.com OR turkishairlines.com OR ryanair.com OR easyjet.com',
            'OR united.com OR delta.com OR aa.com OR southwest.com OR jetblue.com OR aircanada.com',
            'OR jal.com OR koreanair.com OR qantas.com',
            'OR makemytrip.com OR goibibo.com OR cleartrip.com OR easemytrip.com OR yatra.com OR ixigo.com OR via.com OR paytm.com',
            'OR happyeasygo.com OR abhibus.com OR thomascook.in OR sotc.in OR akbartravels.com OR musafir.com OR adanione.com OR udchalo.com',
            'OR phonepe.com OR amazon.in OR flipkart.com',
            'OR expedia.com OR booking.com OR kayak.com OR skyscanner.com OR trip.com OR kiwi.com OR traveloka.com OR agoda.com)',
            'subject:(booking OR confirmation OR e-ticket OR eticket OR itinerary OR PNR OR flight OR "boarding pass" OR ticket OR reservation)',
            '-subject:(deal OR offer OR sale OR "price alert" OR newsletter OR unsubscribe)',
        ].join(' ');
        const { messages, moreBatches, totalEmails } = await gmailService.fetchEmails(query, {
            batchSize,
            batch,
        });
        console.log(`scanFlightEmails: Fetched ${messages.length} emails (batch ${batch}), ` +
            `totalEmails=${totalEmails}, moreBatches=${moreBatches}`);
        let detectedCount = 0;
        for (const message of messages) {
            const detection = (0, flightDetector_1.detectFlightEmail)(message);
            if (detection.isFlightEmail) {
                console.log(`scanFlightEmails: FLIGHT DETECTED [${detection.confidence}] score=${detection.score} ` +
                    `subject="${message.subject}"`);
                await storeDetectedFlightEmail(userId, message, detection, 'batch_scan');
                detectedCount++;
            }
        }
        console.log(`scanFlightEmails: batch ${batch} complete — ${detectedCount} flights detected from ${messages.length} emails`);
        return {
            success: true,
            batch,
            totalEmails,
            scannedInBatch: messages.length,
            detectedInBatch: detectedCount,
            moreBatches,
            nextBatch: moreBatches ? batch + 1 : null,
        };
    }
    catch (error) {
        console.error('scanFlightEmails error:', error);
        throw new functions.https.HttpsError('internal', `Failed to scan flight emails: ${error.message}`);
    }
});
//# sourceMappingURL=index.js.map