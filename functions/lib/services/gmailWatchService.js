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
exports.GmailWatchService = void 0;
const googleapis_1 = require("googleapis");
const admin = __importStar(require("firebase-admin"));
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const GMAIL_PUBSUB_TOPIC = process.env.GMAIL_PUBSUB_TOPIC || 'projects/moneytest-app/topics/gmail-notifications';
/**
 * Gmail Watch Service
 * Manages Gmail push notification subscriptions
 */
class GmailWatchService {
    constructor() {
        this.db = admin.firestore();
    }
    /**
     * Create OAuth2 client with user's refresh token
     */
    async getOAuth2Client(userId) {
        if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
            throw new Error('Google OAuth credentials not configured');
        }
        // Get refresh token from Firestore
        const userDoc = await this.db.collection('users').doc(userId).get();
        const userData = userDoc.data();
        if (!userData?.gmailRefreshToken) {
            throw new Error('No refresh token found for user');
        }
        const oauth2Client = new googleapis_1.google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET);
        oauth2Client.setCredentials({
            refresh_token: userData.gmailRefreshToken,
        });
        return oauth2Client;
    }
    /**
     * Set up Gmail watch for a user
     * This subscribes the user's Gmail to push notifications
     */
    async setupWatch(userId) {
        if (!GMAIL_PUBSUB_TOPIC) {
            throw new Error('Gmail Pub/Sub topic not configured');
        }
        const oauth2Client = await this.getOAuth2Client(userId);
        const gmail = googleapis_1.google.gmail({ version: 'v1', auth: oauth2Client });
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
    async stopWatch(userId) {
        const oauth2Client = await this.getOAuth2Client(userId);
        const gmail = googleapis_1.google.gmail({ version: 'v1', auth: oauth2Client });
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
    async getNewMessages(userId, startHistoryId) {
        const oauth2Client = await this.getOAuth2Client(userId);
        const gmail = googleapis_1.google.gmail({ version: 'v1', auth: oauth2Client });
        const response = await gmail.users.history.list({
            userId: 'me',
            startHistoryId,
            historyTypes: ['messageAdded'],
        });
        const messageIds = [];
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
    async getAccessToken(userId) {
        const oauth2Client = await this.getOAuth2Client(userId);
        const { token } = await oauth2Client.getAccessToken();
        if (!token) {
            throw new Error('Failed to get access token');
        }
        return token;
    }
}
exports.GmailWatchService = GmailWatchService;
//# sourceMappingURL=gmailWatchService.js.map