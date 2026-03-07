import { google } from 'googleapis';
import * as admin from 'firebase-admin';

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const GMAIL_PUBSUB_TOPIC = process.env.GMAIL_PUBSUB_TOPIC || 'projects/moneytest-app/topics/gmail-notifications';

/**
 * Gmail Watch Service
 * Manages Gmail push notification subscriptions
 */
export class GmailWatchService {
  private db: admin.firestore.Firestore;

  constructor() {
    this.db = admin.firestore();
  }

  /**
   * Create OAuth2 client with user's refresh token
   */
  private async getOAuth2Client(userId: string) {
    if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
      throw new Error('Google OAuth credentials not configured');
    }

    // Get refresh token from Firestore
    const userDoc = await this.db.collection('users').doc(userId).get();
    const userData = userDoc.data();

    if (!userData?.gmailRefreshToken) {
      throw new Error('No refresh token found for user');
    }

    const oauth2Client = new google.auth.OAuth2(
      GOOGLE_CLIENT_ID,
      GOOGLE_CLIENT_SECRET
    );

    oauth2Client.setCredentials({
      refresh_token: userData.gmailRefreshToken,
    });

    return oauth2Client;
  }

  /**
   * Set up Gmail watch for a user
   * This subscribes the user's Gmail to push notifications
   */
  async setupWatch(userId: string): Promise<{ historyId: string; expiration: string }> {
    if (!GMAIL_PUBSUB_TOPIC) {
      throw new Error('Gmail Pub/Sub topic not configured');
    }

    const oauth2Client = await this.getOAuth2Client(userId);
    const gmail = google.gmail({ version: 'v1', auth: oauth2Client });

    // Set up watch on user's inbox
    const response = await gmail.users.watch({
      userId: 'me',
      requestBody: {
        topicName: GMAIL_PUBSUB_TOPIC,
        labelIds: ['INBOX'],
      },
    });

    const historyId = response.data.historyId || '';
    const expiration = response.data.expiration || '';

    // Store watch info in Firestore
    await this.db.collection('users').doc(userId).update({
      gmailWatchHistoryId: historyId,
      gmailWatchExpiration: expiration,
      gmailWatchSetupAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`Gmail watch set up for user ${userId}, historyId: ${historyId}, expires: ${expiration}`);

    return { historyId, expiration };
  }

  /**
   * Stop Gmail watch for a user
   */
  async stopWatch(userId: string): Promise<void> {
    const oauth2Client = await this.getOAuth2Client(userId);
    const gmail = google.gmail({ version: 'v1', auth: oauth2Client });

    await gmail.users.stop({ userId: 'me' });

    // Clear watch info in Firestore
    await this.db.collection('users').doc(userId).update({
      gmailWatchHistoryId: admin.firestore.FieldValue.delete(),
      gmailWatchExpiration: admin.firestore.FieldValue.delete(),
      gmailWatchSetupAt: admin.firestore.FieldValue.delete(),
    });

    console.log(`Gmail watch stopped for user ${userId}`);
  }

  /**
   * Get new messages since last history ID
   */
  async getNewMessages(userId: string, startHistoryId: string): Promise<string[]> {
    const oauth2Client = await this.getOAuth2Client(userId);
    const gmail = google.gmail({ version: 'v1', auth: oauth2Client });

    const response = await gmail.users.history.list({
      userId: 'me',
      startHistoryId,
      historyTypes: ['messageAdded'],
    });

    const messageIds: string[] = [];

    if (response.data.history) {
      for (const history of response.data.history) {
        if (history.messagesAdded) {
          for (const added of history.messagesAdded) {
            if (added.message?.id) {
              messageIds.push(added.message.id);
            }
          }
        }
      }
    }

    return messageIds;
  }

  /**
   * Get fresh access token for a user
   */
  async getAccessToken(userId: string): Promise<string> {
    const oauth2Client = await this.getOAuth2Client(userId);
    const { token } = await oauth2Client.getAccessToken();

    if (!token) {
      throw new Error('Failed to get access token');
    }

    return token;
  }
}
