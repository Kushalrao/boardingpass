import * as admin from 'firebase-admin';

export interface NotificationPayload {
  title: string;
  body: string;
  data?: { [key: string]: string };
}

/**
 * FCM Service for sending push notifications
 */
export class FcmService {
  private db: admin.firestore.Firestore;

  constructor() {
    this.db = admin.firestore();
  }

  /**
   * Send notification to a specific user
   */
  async sendToUser(userId: string, notification: NotificationPayload): Promise<number> {
    const userDoc = await this.db.collection('users').doc(userId).get();
    const userData = userDoc.data();

    if (!userData?.fcmTokens || userData.fcmTokens.length === 0) {
      console.log(`No FCM tokens for user: ${userId}`);
      return 0;
    }

    const tokens = userData.fcmTokens.map((t: any) => t.token);
    return this.sendToTokens(tokens, notification, userId);
  }

  /**
   * Send notification to multiple tokens
   */
  async sendToTokens(
    tokens: string[],
    notification: NotificationPayload,
    userId?: string
  ): Promise<number> {
    if (tokens.length === 0) return 0;

    const message: admin.messaging.MulticastMessage = {
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
        const invalidTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const errorCode = resp.error?.code;
            if (
              errorCode === 'messaging/invalid-registration-token' ||
              errorCode === 'messaging/registration-token-not-registered'
            ) {
              invalidTokens.push(tokens[idx]);
            }
          }
        });

        if (invalidTokens.length > 0) {
          await this.removeInvalidTokens(userId, invalidTokens);
        }
      }

      return response.successCount;
    } catch (error) {
      console.error('Error sending FCM notification:', error);
      return 0;
    }
  }

  /**
   * Remove invalid tokens from user's document
   */
  private async removeInvalidTokens(userId: string, invalidTokens: string[]): Promise<void> {
    try {
      const userDoc = await this.db.collection('users').doc(userId).get();
      const userData = userDoc.data();

      if (userData?.fcmTokens) {
        const validTokens = userData.fcmTokens.filter(
          (t: any) => !invalidTokens.includes(t.token)
        );

        await this.db.collection('users').doc(userId).update({
          fcmTokens: validTokens,
        });

        console.log(`Removed ${invalidTokens.length} invalid tokens for user: ${userId}`);
      }
    } catch (error) {
      console.error('Error removing invalid tokens:', error);
    }
  }

  /**
   * Format flight status notification
   */
  static formatFlightStatusNotification(
    flightNumber: string,
    eventType: string,
    details: any
  ): NotificationPayload {
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
  static formatFlightDiscoveredNotification(
    flightNumber: string,
    origin: string,
    destination: string,
    departureDate: string
  ): NotificationPayload {
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
