import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { google } from 'googleapis';
import { GmailService } from './services/gmailService';
import { GmailWatchService } from './services/gmailWatchService';
import { detectFlightEmail } from './services/flightDetector';

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

async function storeDetectedFlightEmail(
  userId: string,
  message: { id: string; subject: string; from: string; date: string; body: string; pdfAttachments: { filename: string; attachmentId: string }[] },
  detection: ReturnType<typeof detectFlightEmail>,
  source: 'webhook' | 'batch_scan'
): Promise<void> {
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
export const gmailWebhook = functions
  .runWith({
    timeoutSeconds: 120,
    memory: '256MB',
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

    try {
      const watchService = new GmailWatchService();

      // Get new message IDs since last history checkpoint
      const newMessageIds = await watchService.getNewMessages(userId, lastHistoryId);
      console.log(
        `gmailWebhook: ${newMessageIds.length} new messages for user ${userId}`
      );

      if (newMessageIds.length === 0) {
        // Update historyId even if no new messages
        await db.collection('users').doc(userId).update({
          gmailWatchHistoryId: historyId,
        });
        return;
      }

      // Get a fresh access token for fetching email content
      const accessToken = await watchService.getAccessToken(userId);
      const gmailService = new GmailService(accessToken);

      // Fetch and analyze each new email
      for (const messageId of newMessageIds) {
        try {
          const message = await gmailService.fetchMessageById(messageId);
          if (!message) {
            console.warn(`gmailWebhook: Could not fetch message ${messageId}`);
            continue;
          }

          // Run flight detection
          const detection = detectFlightEmail(message);

          if (detection.isFlightEmail) {
            console.log(
              `gmailWebhook: FLIGHT DETECTED [${detection.confidence}] score=${detection.score} ` +
              `signals=[${detection.matchedSignals.join(', ')}] subject="${message.subject}"`
            );

            await storeDetectedFlightEmail(userId, message, detection, 'webhook');
          }
        } catch (err) {
          console.error(`gmailWebhook: Error processing message ${messageId}:`, err);
          continue;
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
export const scanFlightEmails = functions
  .runWith({
    timeoutSeconds: 300,
    memory: '512MB',
  })
  .https.onCall(async (data: { batch?: number; batchSize?: number }, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    const userId = context.auth.uid;
    const batch = data?.batch || 1;
    const batchSize = Math.min(data?.batchSize || 20, 50);

    console.log(`scanFlightEmails: user=${userId}, batch=${batch}, batchSize=${batchSize}`);

    try {
      // Get access token via refresh token
      const watchService = new GmailWatchService();
      const accessToken = await watchService.getAccessToken(userId);
      const gmailService = new GmailService(accessToken);

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

      console.log(
        `scanFlightEmails: Fetched ${messages.length} emails (batch ${batch}), ` +
        `totalEmails=${totalEmails}, moreBatches=${moreBatches}`
      );

      let detectedCount = 0;

      for (const message of messages) {
        const detection = detectFlightEmail(message);

        if (detection.isFlightEmail) {
          console.log(
            `scanFlightEmails: FLIGHT DETECTED [${detection.confidence}] score=${detection.score} ` +
            `subject="${message.subject}"`
          );

          await storeDetectedFlightEmail(userId, message, detection, 'batch_scan');
          detectedCount++;
        }
      }

      console.log(
        `scanFlightEmails: batch ${batch} complete — ${detectedCount} flights detected from ${messages.length} emails`
      );

      return {
        success: true,
        batch,
        totalEmails,
        scannedInBatch: messages.length,
        detectedInBatch: detectedCount,
        moreBatches,
        nextBatch: moreBatches ? batch + 1 : null,
      };
    } catch (error: any) {
      console.error('scanFlightEmails error:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Failed to scan flight emails: ${error.message}`
      );
    }
  });
