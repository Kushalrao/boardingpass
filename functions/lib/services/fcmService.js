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
exports.FcmService = void 0;
const admin = __importStar(require("firebase-admin"));
/**
 * FCM Service for sending push notifications
 */
class FcmService {
    constructor() {
        this.db = admin.firestore();
    }
    /**
     * Send notification to a specific user
     */
    async sendToUser(userId, notification) {
        const userDoc = await this.db.collection('users').doc(userId).get();
        const userData = userDoc.data();
        if (!userData?.fcmTokens || userData.fcmTokens.length === 0) {
            console.log(`No FCM tokens for user: ${userId}`);
            return 0;
        }
        const tokens = userData.fcmTokens.map((t) => t.token);
        return this.sendToTokens(tokens, notification, userId);
    }
    /**
     * Send notification to multiple tokens
     */
    async sendToTokens(tokens, notification, userId) {
        if (tokens.length === 0)
            return 0;
        const message = {
            tokens,
            notification: {
                title: notification.title,
                body: notification.body,
            },
            data: notification.data,
            android: {
                notification: {
                    channelId: 'flight_status',
                    priority: 'high',
                },
            },
            apns: {
                payload: {
                    aps: {
                        alert: {
                            title: notification.title,
                            body: notification.body,
                        },
                        sound: 'default',
                        badge: 1,
                    },
                },
            },
        };
        try {
            const response = await admin.messaging().sendEachForMulticast(message);
            console.log(`Sent ${response.successCount}/${tokens.length} notifications`);
            // Clean up invalid tokens
            if (response.failureCount > 0 && userId) {
                const invalidTokens = [];
                response.responses.forEach((resp, idx) => {
                    if (!resp.success) {
                        const errorCode = resp.error?.code;
                        if (errorCode === 'messaging/invalid-registration-token' ||
                            errorCode === 'messaging/registration-token-not-registered') {
                            invalidTokens.push(tokens[idx]);
                        }
                    }
                });
                if (invalidTokens.length > 0) {
                    await this.removeInvalidTokens(userId, invalidTokens);
                }
            }
            return response.successCount;
        }
        catch (error) {
            console.error('Error sending FCM notification:', error);
            return 0;
        }
    }
    /**
     * Remove invalid tokens from user's document
     */
    async removeInvalidTokens(userId, invalidTokens) {
        try {
            const userDoc = await this.db.collection('users').doc(userId).get();
            const userData = userDoc.data();
            if (userData?.fcmTokens) {
                const validTokens = userData.fcmTokens.filter((t) => !invalidTokens.includes(t.token));
                await this.db.collection('users').doc(userId).update({
                    fcmTokens: validTokens,
                });
                console.log(`Removed ${invalidTokens.length} invalid tokens for user: ${userId}`);
            }
        }
        catch (error) {
            console.error('Error removing invalid tokens:', error);
        }
    }
    /**
     * Format flight status notification
     */
    static formatFlightStatusNotification(flightNumber, eventType, details) {
        let title = '';
        let body = '';
        switch (eventType) {
            case 'DEPARTURE':
                title = `${flightNumber} Departed`;
                body = `Your flight has departed from ${details.departureAirport || 'the gate'}`;
                break;
            case 'ARRIVAL':
                title = `${flightNumber} Arrived`;
                body = `Your flight has arrived at ${details.arrivalAirport || 'the destination'}`;
                break;
            case 'DELAY':
                title = `${flightNumber} Delayed`;
                body = details.delayMinutes
                    ? `Your flight is delayed by ${details.delayMinutes} minutes`
                    : 'Your flight has been delayed';
                break;
            case 'GATE_CHANGE':
                title = `${flightNumber} Gate Change`;
                body = details.newGate
                    ? `Gate changed to ${details.newGate}`
                    : 'Your gate has changed';
                break;
            case 'CANCELLATION':
                title = `${flightNumber} Cancelled`;
                body = 'Your flight has been cancelled';
                break;
            case 'DIVERSION':
                title = `${flightNumber} Diverted`;
                body = details.diversionAirport
                    ? `Your flight is being diverted to ${details.diversionAirport}`
                    : 'Your flight has been diverted';
                break;
            case 'BAGGAGE':
                title = `${flightNumber} Baggage Info`;
                body = details.baggageBelt
                    ? `Collect your baggage at belt ${details.baggageBelt}`
                    : 'Baggage information updated';
                break;
            default:
                title = `${flightNumber} Update`;
                body = 'Your flight status has been updated';
        }
        return {
            title,
            body,
            data: {
                flightNumber,
                eventType,
                ...details,
            },
        };
    }
    /**
     * Format flight discovered notification (from Gmail)
     */
    static formatFlightDiscoveredNotification(flightNumber, origin, destination, departureDate) {
        return {
            title: 'Flight Added',
            body: `We found your ${flightNumber} flight from ${origin} to ${destination} on ${departureDate}`,
            data: {
                type: 'flight_discovered',
                flightNumber,
                origin,
                destination,
                departureDate,
            },
        };
    }
}
exports.FcmService = FcmService;
//# sourceMappingURL=fcmService.js.map