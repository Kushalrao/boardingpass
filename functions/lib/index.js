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
exports.onFlightDeleted = exports.onFlightCreated = exports.deleteFlightAlert = exports.createFlightAlert = exports.ciriumAlertWebhook = exports.gmailWebhook = exports.setupGmailWatch = exports.storeRefreshToken = exports.analyzeTravel = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const googleapis_1 = require("googleapis");
const gmailService_1 = require("./services/gmailService");
const gmailWatchService_1 = require("./services/gmailWatchService");
const pdfService_1 = require("./services/pdfService");
const openaiService_1 = require("./services/openaiService");
const ciriumAlertService_1 = require("./services/ciriumAlertService");
const ciriumRatingsService_1 = require("./services/ciriumRatingsService");
const ciriumFlightStatusService_1 = require("./services/ciriumFlightStatusService");
const ciriumWeatherService_1 = require("./services/ciriumWeatherService");
const ciriumEquipmentService_1 = require("./services/ciriumEquipmentService");
const fcmService_1 = require("./services/fcmService");
const bookingDetector_1 = require("./utils/bookingDetector");
// Initialize Firebase Admin
if (!admin.apps.length) {
    admin.initializeApp();
}
// Environment variables
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const CIRIUM_WEBHOOK_URL = process.env.CIRIUM_WEBHOOK_URL || 'https://us-central1-airtime-4e65f.cloudfunctions.net/ciriumAlertWebhook';
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
            // Only process flight bookings
            if (bookingType !== 'flight') {
                console.log(`Skipping non-flight booking: ${bookingType}`);
                continue;
            }
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
    // Verify user is authenticated
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
        // Create OAuth2 client
        const oauth2Client = new googleapis_1.google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, '' // No redirect URI needed for mobile auth code exchange
        );
        // Exchange auth code for tokens
        const { tokens } = await oauth2Client.getToken(authCode);
        if (!tokens.refresh_token) {
            console.log('No refresh token returned - user may have already authorized');
            throw new functions.https.HttpsError('failed-precondition', 'No refresh token returned. User may need to revoke app access and re-authorize.');
        }
        // Store refresh token in Firestore
        const db = admin.firestore();
        await db.collection('users').doc(userId).update({
            gmailRefreshToken: tokens.refresh_token,
            gmailTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log('Refresh token stored successfully');
        return { success: true };
    }
    catch (error) {
        console.error('Error storing refresh token:', error);
        throw new functions.https.HttpsError('internal', `Failed to store refresh token: ${error.message}`);
    }
});
/**
 * Set up Gmail watch for push notifications
 * Call this after storing refresh token to start receiving new email notifications
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
/**
 * Gmail webhook handler - receives Pub/Sub notifications when new emails arrive
 * This is triggered by Google Cloud Pub/Sub
 */
exports.gmailWebhook = functions.pubsub
    .topic('gmail-notifications') // Must match your Pub/Sub topic name
    .onPublish(async (message) => {
    console.log('Received Gmail notification');
    // Decode the Pub/Sub message
    const data = message.json;
    const emailAddress = data.emailAddress;
    const historyId = data.historyId;
    console.log(`Email: ${emailAddress}, HistoryId: ${historyId}`);
    // Find user by email
    const db = admin.firestore();
    const usersSnapshot = await db
        .collection('users')
        .where('email', '==', emailAddress)
        .limit(1)
        .get();
    if (usersSnapshot.empty) {
        console.log(`No user found for email: ${emailAddress}`);
        return;
    }
    const userDoc = usersSnapshot.docs[0];
    const userId = userDoc.id;
    const userData = userDoc.data();
    const lastHistoryId = userData.gmailWatchHistoryId;
    console.log(`Processing for user: ${userId}, last historyId: ${lastHistoryId}`);
    try {
        const watchService = new gmailWatchService_1.GmailWatchService();
        // Get new message IDs since last history
        const messageIds = await watchService.getNewMessages(userId, lastHistoryId);
        console.log(`Found ${messageIds.length} new messages`);
        if (messageIds.length === 0) {
            // Update history ID even if no new messages
            await db.collection('users').doc(userId).update({
                gmailWatchHistoryId: historyId,
            });
            return;
        }
        // Get access token for processing
        const accessToken = await watchService.getAccessToken(userId);
        // Initialize services
        const gmailService = new gmailService_1.GmailService(accessToken);
        const pdfService = new pdfService_1.PdfService();
        const openaiService = new openaiService_1.OpenAIService(OPENAI_API_KEY);
        // Process each new message
        for (const messageId of messageIds) {
            try {
                // Fetch full message
                const message = await gmailService.fetchMessageById(messageId);
                if (!message) {
                    console.log(`Could not fetch message: ${messageId}`);
                    continue;
                }
                // Detect booking type
                const bookingType = (0, bookingDetector_1.detectBookingType)(message.subject, message.from);
                console.log(`Message ${messageId}: type=${bookingType}`);
                // Only process flight bookings
                if (bookingType !== 'flight') {
                    console.log(`Skipping non-flight booking: ${bookingType}`);
                    continue;
                }
                // Extract content (PDF or body)
                let content = '';
                if (message.pdfAttachments.length > 0) {
                    for (const pdf of message.pdfAttachments) {
                        try {
                            const pdfBuffer = await gmailService.fetchPdfAttachment(messageId, pdf.attachmentId);
                            content = await pdfService.extractText(pdfBuffer);
                            break;
                        }
                        catch (e) {
                            console.error(`PDF parse error: ${e}`);
                        }
                    }
                }
                if (!content && message.body) {
                    content = message.body;
                }
                if (!content) {
                    console.log(`No content for message: ${messageId}`);
                    continue;
                }
                // Extract booking data
                const bookingData = await openaiService.extractBookingData(content, bookingType);
                if (bookingData && Object.keys(bookingData).length > 0) {
                    // Fetch performance ratings if flight data available
                    let performanceRating = null;
                    if ('flights' in bookingData && bookingData.flights?.[0]) {
                        const flight = bookingData.flights[0];
                        // Extract carrier code from flight_number (e.g., "AI111" -> "AI")
                        const flightNum = flight.flight_number || '';
                        const carrierMatch = flightNum.match(/^([A-Z]{2})/);
                        const carrier = carrierMatch ? carrierMatch[1] : null;
                        const numericFlightNum = flightNum.replace(/^[A-Z]+/, '');
                        const depAirport = flight.departure?.airport_code || undefined;
                        const arrAirport = flight.arrival?.airport_code || undefined;
                        if (carrier && numericFlightNum) {
                            try {
                                const ratingsService = new ciriumRatingsService_1.CiriumRatingsService();
                                const rating = await ratingsService.getFlightRatings(carrier, numericFlightNum, depAirport, arrAirport);
                                if (rating) {
                                    performanceRating = ratingsService.formatForStorage(rating);
                                    console.log(`Fetched rating for ${carrier}${numericFlightNum}: ${performanceRating.ontimePercent}% on-time`);
                                }
                            }
                            catch (e) {
                                console.error('Error fetching ratings:', e);
                            }
                        }
                    }
                    // Store in user's travels collection
                    await db.collection('users').doc(userId).collection('travels').doc(messageId).set({
                        ...bookingData,
                        booking_type: bookingType,
                        date: message.date,
                        emailMessageId: messageId,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        source: 'webhook', // Mark as automatically fetched
                        ...(performanceRating && { performanceRating }),
                    });
                    console.log(`Stored flight booking from message: ${messageId}`);
                }
            }
            catch (error) {
                console.error(`Error processing message ${messageId}:`, error);
            }
        }
        // Update history ID
        await db.collection('users').doc(userId).update({
            gmailWatchHistoryId: historyId,
        });
        console.log(`Finished processing for user: ${userId}`);
    }
    catch (error) {
        console.error('Error in Gmail webhook:', error);
    }
});
/**
 * Cirium Alert Webhook
 * Receives flight status updates from Cirium Alerts API
 */
exports.ciriumAlertWebhook = functions
    .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
})
    .https.onRequest(async (req, res) => {
    // Only accept POST requests
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    console.log('Received Cirium alert:', JSON.stringify(req.body));
    try {
        const alertData = req.body;
        // Extract flight info from alert
        const flightNumber = `${alertData.carrierFsCode}${alertData.flightNumber}`;
        const departureAirport = alertData.departureAirportFsCode;
        const arrivalAirport = alertData.arrivalAirportFsCode;
        const ruleId = alertData.rule?.id;
        // Determine event type from alert
        let eventType = 'STATUS_UPDATE';
        const details = {
            departureAirport,
            arrivalAirport,
        };
        // Parse the alert event
        if (alertData.event) {
            const event = alertData.event;
            if (event.type === 'DEPARTURE') {
                eventType = 'DEPARTURE';
            }
            else if (event.type === 'ARRIVAL') {
                eventType = 'ARRIVAL';
            }
            else if (event.type === 'CANCELLATION') {
                eventType = 'CANCELLATION';
            }
            else if (event.type === 'DIVERSION') {
                eventType = 'DIVERSION';
                details.diversionAirport = event.diversionAirport;
            }
            else if (event.type === 'DELAY' || event.type === 'DEPARTURE_DELAY') {
                eventType = 'DELAY';
                details.delayMinutes = event.delayMinutes;
            }
            else if (event.type === 'GATE_DEPARTURE' || event.type === 'GATE_CHANGE') {
                eventType = 'GATE_CHANGE';
                details.newGate = event.gate;
            }
            else if (event.type === 'BAGGAGE') {
                eventType = 'BAGGAGE';
                details.baggageBelt = event.baggage;
            }
        }
        // Find users tracking this flight
        const db = admin.firestore();
        const flightsSnapshot = await db
            .collectionGroup('flights')
            .where('ciriumAlertRuleId', '==', ruleId)
            .get();
        if (flightsSnapshot.empty) {
            console.log(`No users found tracking alert rule: ${ruleId}`);
            res.status(200).send('OK - No users tracking');
            return;
        }
        // Send notifications to all users tracking this flight
        const fcmService = new fcmService_1.FcmService();
        const notification = fcmService_1.FcmService.formatFlightStatusNotification(flightNumber, eventType, details);
        let successCount = 0;
        for (const flightDoc of flightsSnapshot.docs) {
            const userId = flightDoc.ref.parent.parent?.id;
            if (userId) {
                const sent = await fcmService.sendToUser(userId, notification);
                successCount += sent;
                // Update flight document with latest status
                await flightDoc.ref.update({
                    lastAlertType: eventType,
                    lastAlertAt: admin.firestore.FieldValue.serverTimestamp(),
                    lastAlertDetails: details,
                });
            }
        }
        console.log(`Sent ${successCount} notifications for ${flightNumber} ${eventType}`);
        res.status(200).send('OK');
    }
    catch (error) {
        console.error('Error processing Cirium alert:', error);
        res.status(500).send('Internal Server Error');
    }
});
/**
 * Create Cirium Alert for a tracked flight
 * Called when a user adds a flight to track
 */
exports.createFlightAlert = functions
    .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
})
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const { flightId, carrier, flightNumber, departureAirport, departureDate } = data;
    if (!flightId || !carrier || !flightNumber || !departureAirport || !departureDate) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required flight information');
    }
    const userId = context.auth.uid;
    console.log(`Creating Cirium alert for ${carrier}${flightNumber} for user ${userId}`);
    try {
        // Parse departure date
        const date = new Date(departureDate);
        const year = date.getFullYear();
        const month = date.getMonth() + 1;
        const day = date.getDate();
        // Create Cirium alert
        const ciriumService = new ciriumAlertService_1.CiriumAlertService(CIRIUM_WEBHOOK_URL);
        const result = await ciriumService.createAlert(carrier, flightNumber, departureAirport, year, month, day);
        if (!result) {
            throw new functions.https.HttpsError('internal', 'Failed to create Cirium alert');
        }
        // Store alert rule ID in flight document
        const db = admin.firestore();
        await db.collection('users').doc(userId).collection('flights').doc(flightId).update({
            ciriumAlertRuleId: result.rule.id,
            ciriumAlertCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
            alertCapabilities: result.alertCapabilities,
        });
        console.log(`Created Cirium alert ${result.rule.id} for flight ${flightId}`);
        return {
            success: true,
            ruleId: result.rule.id,
            alertCapabilities: result.alertCapabilities,
        };
    }
    catch (error) {
        console.error('Error creating flight alert:', error);
        throw new functions.https.HttpsError('internal', `Failed to create flight alert: ${error.message}`);
    }
});
/**
 * Delete Cirium Alert when flight is removed
 */
exports.deleteFlightAlert = functions
    .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
})
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const { ruleId } = data;
    if (!ruleId) {
        throw new functions.https.HttpsError('invalid-argument', 'Rule ID is required');
    }
    console.log(`Deleting Cirium alert: ${ruleId}`);
    try {
        const ciriumService = new ciriumAlertService_1.CiriumAlertService(CIRIUM_WEBHOOK_URL);
        const success = await ciriumService.deleteAlert(ruleId);
        return { success };
    }
    catch (error) {
        console.error('Error deleting flight alert:', error);
        throw new functions.https.HttpsError('internal', `Failed to delete flight alert: ${error.message}`);
    }
});
/**
 * Firestore trigger: Auto-create Cirium alert when flight is added
 * Also fetches and stores flight performance ratings
 */
exports.onFlightCreated = functions.firestore
    .document('users/{userId}/flights/{flightId}')
    .onCreate(async (snapshot, context) => {
    const { userId } = context.params;
    const flightData = snapshot.data();
    const carrier = flightData.carrierFsCode || '';
    const flightNumber = flightData.flightNumber || '';
    const fullFlightNumber = `${carrier}${flightNumber}`;
    const departureAirport = flightData.originAirport;
    const arrivalAirport = flightData.destinationAirport;
    const originCity = flightData.originCity || departureAirport;
    const destinationCity = flightData.destinationCity || arrivalAirport;
    const departureDate = flightData.departureDate || flightData.departureTime?.split('T')[0];
    // Send "Flight Added" notification
    console.log(`Sending flight added notification for ${fullFlightNumber} to user ${userId}`);
    try {
        const fcmService = new fcmService_1.FcmService();
        const notification = {
            title: 'Flight Added',
            body: `${fullFlightNumber} from ${originCity} to ${destinationCity} has been added to your trips`,
            data: {
                type: 'flight_added',
                flightNumber: fullFlightNumber,
                origin: originCity,
                destination: destinationCity,
            },
        };
        await fcmService.sendToUser(userId, notification);
    }
    catch (error) {
        console.error('Error sending flight added notification:', error);
    }
    // Fetch and store Cirium data (ratings, flight status, weather, equipment)
    if (carrier && flightNumber && departureDate) {
        console.log(`Fetching Cirium data for ${fullFlightNumber}`);
        const ciriumData = {};
        const date = new Date(departureDate);
        const year = date.getFullYear();
        const month = date.getMonth() + 1;
        const day = date.getDate();
        // Fetch all data in parallel
        const [ratingsResult, flightStatusResult, depWeatherResult, arrWeatherResult] = await Promise.all([
            // 1. Performance ratings
            (async () => {
                try {
                    const ratingsService = new ciriumRatingsService_1.CiriumRatingsService();
                    const rating = await ratingsService.getFlightRatings(carrier, flightNumber, departureAirport, arrivalAirport);
                    if (rating) {
                        return ratingsService.formatForStorage(rating);
                    }
                }
                catch (e) {
                    console.error('Error fetching ratings:', e);
                }
                return null;
            })(),
            // 2. Flight status
            (async () => {
                try {
                    const flightStatusService = new ciriumFlightStatusService_1.CiriumFlightStatusService();
                    const result = await flightStatusService.getFlightStatus(carrier, flightNumber, year, month, day);
                    if (result) {
                        return flightStatusService.formatForStorage(result.status, result.appendix);
                    }
                }
                catch (e) {
                    console.error('Error fetching flight status:', e);
                }
                return null;
            })(),
            // 3. Departure airport weather
            (async () => {
                if (!departureAirport)
                    return null;
                try {
                    const weatherService = new ciriumWeatherService_1.CiriumWeatherService();
                    const weather = await weatherService.getAirportWeather(departureAirport);
                    if (weather) {
                        return weatherService.formatForStorage(weather, departureAirport);
                    }
                }
                catch (e) {
                    console.error('Error fetching departure weather:', e);
                }
                return null;
            })(),
            // 4. Arrival airport weather
            (async () => {
                if (!arrivalAirport)
                    return null;
                try {
                    const weatherService = new ciriumWeatherService_1.CiriumWeatherService();
                    const weather = await weatherService.getAirportWeather(arrivalAirport);
                    if (weather) {
                        return weatherService.formatForStorage(weather, arrivalAirport);
                    }
                }
                catch (e) {
                    console.error('Error fetching arrival weather:', e);
                }
                return null;
            })(),
        ]);
        // Store ratings
        if (ratingsResult) {
            ciriumData.performanceRating = ratingsResult;
            console.log(`Stored performance rating: ${ratingsResult.ontimePercent}% on-time`);
        }
        // Store flight status (includes equipment info)
        if (flightStatusResult) {
            ciriumData.flightStatus = flightStatusResult;
            console.log(`Stored flight status: ${flightStatusResult.status}`);
            // If flight status has equipment, fetch detailed equipment info
            if (flightStatusResult.equipmentCode) {
                try {
                    const equipmentService = new ciriumEquipmentService_1.CiriumEquipmentService();
                    const equipment = await equipmentService.getEquipment(flightStatusResult.equipmentCode);
                    if (equipment) {
                        ciriumData.equipment = equipmentService.formatForStorage(equipment);
                        console.log(`Stored equipment: ${ciriumData.equipment.name}`);
                    }
                }
                catch (e) {
                    console.error('Error fetching equipment:', e);
                }
            }
        }
        // Store weather
        if (depWeatherResult || arrWeatherResult) {
            ciriumData.weather = {
                departure: depWeatherResult,
                arrival: arrWeatherResult,
            };
            console.log(`Stored weather for ${departureAirport}/${arrivalAirport}`);
        }
        // Update flight document with all Cirium data
        if (Object.keys(ciriumData).length > 0) {
            await snapshot.ref.update(ciriumData);
            console.log(`Updated flight with Cirium data: ${Object.keys(ciriumData).join(', ')}`);
        }
    }
    // Skip Cirium alert if already exists or if it's from Gmail webhook
    if (flightData.ciriumAlertRuleId || flightData.source === 'gmail') {
        return;
    }
    if (!carrier || !flightNumber || !departureAirport || !departureDate) {
        console.log('Missing flight info for Cirium alert, skipping');
        return;
    }
    console.log(`Auto-creating Cirium alert for ${fullFlightNumber}`);
    try {
        const date = new Date(departureDate);
        const year = date.getFullYear();
        const month = date.getMonth() + 1;
        const day = date.getDate();
        const ciriumService = new ciriumAlertService_1.CiriumAlertService(CIRIUM_WEBHOOK_URL);
        const result = await ciriumService.createAlert(carrier, flightNumber, departureAirport, year, month, day);
        if (result) {
            await snapshot.ref.update({
                ciriumAlertRuleId: result.rule.id,
                ciriumAlertCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
                alertCapabilities: result.alertCapabilities,
            });
            console.log(`Created Cirium alert ${result.rule.id} for new flight`);
        }
    }
    catch (error) {
        console.error('Error auto-creating Cirium alert:', error);
    }
});
/**
 * Firestore trigger: Auto-delete Cirium alert when flight is removed
 */
exports.onFlightDeleted = functions.firestore
    .document('users/{userId}/flights/{flightId}')
    .onDelete(async (snapshot) => {
    const flightData = snapshot.data();
    const ruleId = flightData.ciriumAlertRuleId;
    if (!ruleId) {
        return;
    }
    console.log(`Auto-deleting Cirium alert: ${ruleId}`);
    try {
        const ciriumService = new ciriumAlertService_1.CiriumAlertService(CIRIUM_WEBHOOK_URL);
        await ciriumService.deleteAlert(ruleId);
        console.log(`Deleted Cirium alert ${ruleId}`);
    }
    catch (error) {
        console.error('Error auto-deleting Cirium alert:', error);
    }
});
//# sourceMappingURL=index.js.map