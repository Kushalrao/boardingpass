import * as http2 from 'http2';
import * as crypto from 'crypto';

const APNS_HOST_PRODUCTION = 'api.push.apple.com';
const APNS_HOST_SANDBOX = 'api.sandbox.push.apple.com';

interface ApnsConfig {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKeyPem: string;  // PEM-encoded .p8 key contents
  sandbox?: boolean;
}

interface LiveActivityContentState {
  status: string;
  departureGate?: string | null;
  arrivalGate?: string | null;
  departureTerminal?: string | null;
  arrivalTerminal?: string | null;
  estimatedDeparture: number;  // Unix timestamp (seconds)
  estimatedArrival: number;    // Unix timestamp (seconds)
  delayMinutes: number;
  progress: number;
  baggageBelt?: string | null;
  diversionAirport?: string | null;
}

/**
 * APNs Service for sending Live Activity push updates.
 * Uses HTTP/2 with JWT (ES256) token-based authentication.
 */
export class ApnsService {
  private config: ApnsConfig;
  private cachedJwt: string | null = null;
  private cachedJwtExpiry: number = 0;

  constructor() {
    const keyP8Base64 = process.env.APNS_KEY_P8 || '';
    const privateKeyPem = keyP8Base64
      ? Buffer.from(keyP8Base64, 'base64').toString('utf-8')
      : '';

    this.config = {
      keyId: process.env.APNS_KEY_ID || '',
      teamId: process.env.APNS_TEAM_ID || '',
      bundleId: process.env.APNS_BUNDLE_ID || 'com.example.airtime',
      privateKeyPem,
      sandbox: process.env.APNS_SANDBOX === 'true',
    };
  }

  /**
   * Generate JWT for APNs authentication (cached for 50 minutes).
   */
  private generateJwt(): string {
    const now = Math.floor(Date.now() / 1000);

    // Reuse cached JWT if still valid (tokens last 1 hour, refresh at 50 min)
    if (this.cachedJwt && now < this.cachedJwtExpiry) {
      return this.cachedJwt;
    }

    const header = {
      alg: 'ES256',
      kid: this.config.keyId,
    };

    const payload = {
      iss: this.config.teamId,
      iat: now,
    };

    const encodedHeader = Buffer.from(JSON.stringify(header)).toString('base64url');
    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signingInput = `${encodedHeader}.${encodedPayload}`;

    const sign = crypto.createSign('SHA256');
    sign.update(signingInput);
    const signature = sign.sign(this.config.privateKeyPem);

    // Convert DER signature to raw r||s format for ES256
    const rawSig = this.derToRaw(signature);
    const encodedSignature = rawSig.toString('base64url');

    this.cachedJwt = `${signingInput}.${encodedSignature}`;
    this.cachedJwtExpiry = now + 3000; // Cache for 50 minutes

    return this.cachedJwt;
  }

  /**
   * Convert DER-encoded ECDSA signature to raw r||s format.
   */
  private derToRaw(derSig: Buffer): Buffer {
    // DER: 0x30 [total-len] 0x02 [r-len] [r] 0x02 [s-len] [s]
    let offset = 2; // skip 0x30 and total length
    const rLen = derSig[offset + 1];
    const r = derSig.subarray(offset + 2, offset + 2 + rLen);
    offset = offset + 2 + rLen;
    const sLen = derSig[offset + 1];
    const s = derSig.subarray(offset + 2, offset + 2 + sLen);

    // Pad or trim to 32 bytes each
    const rPad = Buffer.alloc(32);
    r.copy(rPad, Math.max(0, 32 - r.length), Math.max(0, r.length - 32));
    const sPad = Buffer.alloc(32);
    s.copy(sPad, Math.max(0, 32 - s.length), Math.max(0, s.length - 32));

    return Buffer.concat([rPad, sPad]);
  }

  /**
   * Send a Live Activity update push notification via APNs.
   */
  async sendLiveActivityUpdate(
    pushToken: string,
    contentState: LiveActivityContentState,
    priority: number = 10
  ): Promise<boolean> {
    const payload = {
      aps: {
        timestamp: Math.floor(Date.now() / 1000),
        event: 'update',
        'content-state': contentState,
        'stale-date': Math.floor(Date.now() / 1000) + 3600, // Stale after 1 hour
      },
    };

    return this.sendPush(pushToken, payload, priority);
  }

  /**
   * Send a Live Activity end push notification via APNs.
   */
  async sendLiveActivityEnd(
    pushToken: string,
    contentState: LiveActivityContentState
  ): Promise<boolean> {
    const payload = {
      aps: {
        timestamp: Math.floor(Date.now() / 1000),
        event: 'end',
        'content-state': contentState,
        'dismissal-date': Math.floor(Date.now() / 1000) + 14400, // Keep on screen 4 hours
      },
    };

    return this.sendPush(pushToken, payload, 10);
  }

  /**
   * Send raw APNs push via HTTP/2.
   */
  private sendPush(
    pushToken: string,
    payload: object,
    priority: number
  ): Promise<boolean> {
    if (!this.config.keyId || !this.config.teamId || !this.config.privateKeyPem) {
      console.error('[APNs] Missing configuration — cannot send push');
      return Promise.resolve(false);
    }

    const host = this.config.sandbox ? APNS_HOST_SANDBOX : APNS_HOST_PRODUCTION;
    const topic = `${this.config.bundleId}.push-type.liveactivity`;
    const jwt = this.generateJwt();
    const body = JSON.stringify(payload);

    return new Promise((resolve) => {
      const client = http2.connect(`https://${host}`);

      client.on('error', (err) => {
        console.error('[APNs] Connection error:', err.message);
        resolve(false);
      });

      const req = client.request({
        ':method': 'POST',
        ':path': `/3/device/${pushToken}`,
        'authorization': `bearer ${jwt}`,
        'apns-push-type': 'liveactivity',
        'apns-topic': topic,
        'apns-priority': String(priority),
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(body),
      });

      let responseData = '';

      req.on('response', (headers) => {
        const status = headers[':status'];
        if (status === 200) {
          console.log(`[APNs] Push sent successfully to ${pushToken.substring(0, 8)}...`);
          resolve(true);
        } else {
          console.error(`[APNs] Push failed with status ${status}`);
        }
      });

      req.on('data', (chunk) => {
        responseData += chunk;
      });

      req.on('end', () => {
        if (responseData) {
          try {
            const parsed = JSON.parse(responseData);
            if (parsed.reason) {
              console.error(`[APNs] Error reason: ${parsed.reason}`);
            }
          } catch (_) {
            // Ignore parse errors
          }
        }
        client.close();
        resolve(false);
      });

      req.on('error', (err) => {
        console.error('[APNs] Request error:', err.message);
        client.close();
        resolve(false);
      });

      req.write(body);
      req.end();
    });
  }

  /**
   * Check if APNs is configured.
   */
  isConfigured(): boolean {
    return !!(this.config.keyId && this.config.teamId && this.config.privateKeyPem);
  }
}
