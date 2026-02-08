/**
 * Train Scraper Service
 * HTTP client for calling the Cloud Run train scraper API
 */

import axios, { AxiosInstance } from 'axios';
import {
  PnrStatus,
  TrainSchedule,
  LiveStatus,
  SearchTrainsResult,
} from '../models/train';

export class TrainScraperService {
  private client: AxiosInstance;
  private baseUrl: string;

  constructor() {
    this.baseUrl = process.env.TRAIN_SCRAPER_URL || 'http://localhost:8080';
    this.client = axios.create({
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
  async getPnrStatus(pnr: string): Promise<PnrStatus> {
    try {
      const response = await this.client.get<PnrStatus>(`/pnr/${pnr}`);
      return response.data;
    } catch (error: any) {
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
  async getTrainSchedule(trainNumber: string): Promise<TrainSchedule> {
    try {
      const response = await this.client.get<TrainSchedule>(`/schedule/${trainNumber}`);
      return response.data;
    } catch (error: any) {
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
  async getLiveStatus(trainNumber: string, date?: string): Promise<LiveStatus> {
    try {
      const params = date ? { date } : {};
      const response = await this.client.get<LiveStatus>(`/live/${trainNumber}`, { params });
      return response.data;
    } catch (error: any) {
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
  async searchTrains(from: string, to: string, date?: string): Promise<SearchTrainsResult> {
    try {
      const params: Record<string, string> = {
        from_station: from,
        to_station: to,
      };
      if (date) {
        params.date = date;
      }
      const response = await this.client.get<SearchTrainsResult>('/search', { params });
      return response.data;
    } catch (error: any) {
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
  async healthCheck(): Promise<boolean> {
    try {
      const response = await this.client.get('/health');
      return response.status === 200;
    } catch {
      return false;
    }
  }
}

// Singleton instance
let instance: TrainScraperService | null = null;

export function getTrainScraperService(): TrainScraperService {
  if (!instance) {
    instance = new TrainScraperService();
  }
  return instance;
}
