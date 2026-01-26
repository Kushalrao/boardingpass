"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.CiriumAlertService = void 0;
const axios_1 = __importDefault(require("axios"));
const CIRIUM_APP_ID = process.env.CIRIUM_APP_ID || '5aae456b';
const CIRIUM_APP_KEY = process.env.CIRIUM_APP_KEY || 'b5da0595ab863d6421f5e66b73805e0b';
const CIRIUM_ALERTS_BASE_URL = 'https://api.flightstats.com/flex/alerts/rest/v1/json';
/**
 * Cirium Alert Service
 * Manages flight alert subscriptions via Cirium API
 */
class CiriumAlertService {
    constructor(webhookUrl) {
        this.webhookUrl = webhookUrl;
    }
    /**
     * Create a flight alert subscription
     * Cirium will POST to our webhook when flight status changes
     */
    async createAlert(carrier, flightNumber, departureAirport, year, month, day) {
        try {
            const url = `${CIRIUM_ALERTS_BASE_URL}/create/${carrier}/${flightNumber}/from/${departureAirport}/departing/${year}/${month}/${day}`;
            const response = await axios_1.default.get(url, {
                params: {
                    appId: CIRIUM_APP_ID,
                    appKey: CIRIUM_APP_KEY,
                    deliverTo: this.webhookUrl,
                    type: 'JSON',
                },
            });
            console.log(`Created Cirium alert: ${response.data.rule?.id}`);
            return response.data;
        }
        catch (error) {
            console.error('Error creating Cirium alert:', error.response?.data || error.message);
            return null;
        }
    }
    /**
     * Delete a flight alert subscription
     */
    async deleteAlert(ruleId) {
        try {
            const url = `${CIRIUM_ALERTS_BASE_URL}/delete/${ruleId}`;
            await axios_1.default.get(url, {
                params: {
                    appId: CIRIUM_APP_ID,
                    appKey: CIRIUM_APP_KEY,
                },
            });
            console.log(`Deleted Cirium alert: ${ruleId}`);
            return true;
        }
        catch (error) {
            console.error('Error deleting Cirium alert:', error.response?.data || error.message);
            return false;
        }
    }
    /**
     * List all active alerts
     */
    async listAlerts() {
        try {
            const url = `${CIRIUM_ALERTS_BASE_URL}/list`;
            const response = await axios_1.default.get(url, {
                params: {
                    appId: CIRIUM_APP_ID,
                    appKey: CIRIUM_APP_KEY,
                },
            });
            return response.data.ruleIds || [];
        }
        catch (error) {
            console.error('Error listing Cirium alerts:', error.response?.data || error.message);
            return [];
        }
    }
    /**
     * Get alert details by ID
     */
    async getAlert(ruleId) {
        try {
            const url = `${CIRIUM_ALERTS_BASE_URL}/get/${ruleId}`;
            const response = await axios_1.default.get(url, {
                params: {
                    appId: CIRIUM_APP_ID,
                    appKey: CIRIUM_APP_KEY,
                },
            });
            return response.data.rule || null;
        }
        catch (error) {
            console.error('Error getting Cirium alert:', error.response?.data || error.message);
            return null;
        }
    }
}
exports.CiriumAlertService = CiriumAlertService;
//# sourceMappingURL=ciriumAlertService.js.map