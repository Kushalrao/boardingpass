import axios from 'axios';

const CIRIUM_APP_ID = process.env.CIRIUM_APP_ID || '5aae456b';
const CIRIUM_APP_KEY = process.env.CIRIUM_APP_KEY || 'b5da0595ab863d6421f5e66b73805e0b';
const CIRIUM_ALERTS_BASE_URL = 'https://api.flightstats.com/flex/alerts/rest/v1/json';

export interface CiriumAlertRule {
  id: string;
  carrierFsCode: string;
  flightNumber: string;
  departureAirportFsCode: string;
  arrivalAirportFsCode: string;
  departure: string;
  arrival: string;
}

export interface CreateAlertResponse {
  rule: CiriumAlertRule;
  alertCapabilities: {
    baggage: boolean;
    departureGateChange: boolean;
    arrivalGateChange: boolean;
    gateDeparture: boolean;
    gateArrival: boolean;
    runwayDeparture: boolean;
    runwayArrival: boolean;
  };
}

/**
 * Cirium Alert Service
 * Manages flight alert subscriptions via Cirium API
 */
export class CiriumAlertService {
  private webhookUrl: string;

  constructor(webhookUrl: string) {
    this.webhookUrl = webhookUrl;
  }

  /**
   * Create a flight alert subscription
   * Cirium will POST to our webhook when flight status changes
   */
  async createAlert(
    carrier: string,
    flightNumber: string,
    departureAirport: string,
    year: number,
    month: number,
    day: number
  ): Promise<CreateAlertResponse | null> {
    try {
      const url = `${CIRIUM_ALERTS_BASE_URL}/create/${carrier}/${flightNumber}/from/${departureAirport}/departing/${year}/${month}/${day}`;

      const response = await axios.get(url, {
        params: {
          appId: CIRIUM_APP_ID,
          appKey: CIRIUM_APP_KEY,
          deliverTo: this.webhookUrl,
          type: 'JSON',
        },
      });

      console.log(`Created Cirium alert: ${response.data.rule?.id}`);
      return response.data;
    } catch (error: any) {
      console.error('Error creating Cirium alert:', error.response?.data || error.message);
      return null;
    }
  }

  /**
   * Delete a flight alert subscription
   */
  async deleteAlert(ruleId: string): Promise<boolean> {
    try {
      const url = `${CIRIUM_ALERTS_BASE_URL}/delete/${ruleId}`;

      await axios.get(url, {
        params: {
          appId: CIRIUM_APP_ID,
          appKey: CIRIUM_APP_KEY,
        },
      });

      console.log(`Deleted Cirium alert: ${ruleId}`);
      return true;
    } catch (error: any) {
      console.error('Error deleting Cirium alert:', error.response?.data || error.message);
      return false;
    }
  }

  /**
   * List all active alerts
   */
  async listAlerts(): Promise<string[]> {
    try {
      const url = `${CIRIUM_ALERTS_BASE_URL}/list`;

      const response = await axios.get(url, {
        params: {
          appId: CIRIUM_APP_ID,
          appKey: CIRIUM_APP_KEY,
        },
      });

      return response.data.ruleIds || [];
    } catch (error: any) {
      console.error('Error listing Cirium alerts:', error.response?.data || error.message);
      return [];
    }
  }

  /**
   * Get alert details by ID
   */
  async getAlert(ruleId: string): Promise<CiriumAlertRule | null> {
    try {
      const url = `${CIRIUM_ALERTS_BASE_URL}/get/${ruleId}`;

      const response = await axios.get(url, {
        params: {
          appId: CIRIUM_APP_ID,
          appKey: CIRIUM_APP_KEY,
        },
      });

      return response.data.rule || null;
    } catch (error: any) {
      console.error('Error getting Cirium alert:', error.response?.data || error.message);
      return null;
    }
  }
}
