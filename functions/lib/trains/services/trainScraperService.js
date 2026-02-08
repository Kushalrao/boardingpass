"use strict";
/**
 * Train Scraper Service
 * HTTP client for calling the Cloud Run train scraper API
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.TrainScraperService = void 0;
exports.getTrainScraperService = getTrainScraperService;
const axios_1 = __importDefault(require("axios"));
class TrainScraperService {
    constructor() {
        this.baseUrl = process.env.TRAIN_SCRAPER_URL || 'http://localhost:8080';
        this.client = axios_1.default.create({
            baseURL: this.baseUrl,
            timeout: 60000, // 60 seconds - scraping can be slow
            headers: {
                'Content-Type': 'application/json',
            },
        });
    }
    /**
     * Get PNR status
     */
    async getPnrStatus(pnr) {
        try {
            const response = await this.client.get(`/pnr/${pnr}`);
            return response.data;
        }
        catch (error) {
            console.error(`Error fetching PNR status for ${pnr}:`, error.message);
            return {
                success: false,
                pnr,
                passengers: [],
                error: error.message || 'Failed to fetch PNR status',
            };
        }
    }
    /**
     * Get train schedule
     */
    async getTrainSchedule(trainNumber) {
        try {
            const response = await this.client.get(`/schedule/${trainNumber}`);
            return response.data;
        }
        catch (error) {
            console.error(`Error fetching schedule for ${trainNumber}:`, error.message);
            return {
                success: false,
                trainNumber,
                runningDays: [],
                stations: [],
                error: error.message || 'Failed to fetch train schedule',
            };
        }
    }
    /**
     * Get live running status
     */
    async getLiveStatus(trainNumber, date) {
        try {
            const params = date ? { date } : {};
            const response = await this.client.get(`/live/${trainNumber}`, { params });
            return response.data;
        }
        catch (error) {
            console.error(`Error fetching live status for ${trainNumber}:`, error.message);
            return {
                success: false,
                trainNumber,
                stations: [],
                error: error.message || 'Failed to fetch live status',
            };
        }
    }
    /**
     * Search trains between stations
     */
    async searchTrains(from, to, date) {
        try {
            const params = {
                from_station: from,
                to_station: to,
            };
            if (date) {
                params.date = date;
            }
            const response = await this.client.get('/search', { params });
            return response.data;
        }
        catch (error) {
            console.error(`Error searching trains from ${from} to ${to}:`, error.message);
            return {
                success: false,
                trains: [],
                error: error.message || 'Failed to search trains',
            };
        }
    }
    /**
     * Health check
     */
    async healthCheck() {
        try {
            const response = await this.client.get('/health');
            return response.status === 200;
        }
        catch {
            return false;
        }
    }
}
exports.TrainScraperService = TrainScraperService;
// Singleton instance
let instance = null;
function getTrainScraperService() {
    if (!instance) {
        instance = new TrainScraperService();
    }
    return instance;
}
//# sourceMappingURL=trainScraperService.js.map