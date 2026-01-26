import axios from "axios";

interface FlightRating {
  airlineFsCode: string;
  flightNumber: string;
  departureAirportFsCode: string;
  arrivalAirportFsCode: string;
  observations: number;
  ontime: number;
  late15: number;
  late30: number;
  late45: number;
  cancelled: number;
  diverted: number;
  ontimePercent: number;
  delayObservations: number;
  delayMean: number;
  delayStandardDeviation: number;
  delayMin: number;
  delayMax: number;
  allOntimeStars: number;
  allDelayStars: number;
  allStars: number;
}

interface RatingsResponse {
  ratings: FlightRating[];
}

export class CiriumRatingsService {
  private appId: string;
  private appKey: string;
  private baseUrl = "https://api.flightstats.com/flex/ratings/rest/v1/json";

  constructor() {
    this.appId = process.env.CIRIUM_APP_ID || "";
    this.appKey = process.env.CIRIUM_APP_KEY || "";

    if (!this.appId || !this.appKey) {
      console.warn("[CiriumRatingsService] Missing Cirium credentials");
    }
  }

  /**
   * Get performance ratings for a specific flight
   */
  async getFlightRatings(
    carrier: string,
    flightNumber: string,
    departureAirport?: string,
    arrivalAirport?: string
  ): Promise<FlightRating | null> {
    try {
      let url = `${this.baseUrl}/flight/${carrier}/${flightNumber}`;
      const params: Record<string, string> = {
        appId: this.appId,
        appKey: this.appKey,
      };

      if (departureAirport) {
        params.departureAirport = departureAirport;
      }
      if (arrivalAirport) {
        params.arrivalAirport = arrivalAirport;
      }

      console.log(`[CiriumRatingsService] Fetching ratings for ${carrier}${flightNumber}`);

      const response = await axios.get<RatingsResponse>(url, { params });

      if (response.data.ratings && response.data.ratings.length > 0) {
        // If we have departure/arrival filters, find the matching rating
        if (departureAirport && arrivalAirport) {
          const matchingRating = response.data.ratings.find(
            (r) =>
              r.departureAirportFsCode === departureAirport &&
              r.arrivalAirportFsCode === arrivalAirport
          );
          if (matchingRating) {
            console.log(`[CiriumRatingsService] Found matching rating: ${matchingRating.ontimePercent * 100}% on-time`);
            return matchingRating;
          }
        }

        // Return first rating if no specific match
        const rating = response.data.ratings[0];
        console.log(`[CiriumRatingsService] Found rating: ${rating.ontimePercent * 100}% on-time`);
        return rating;
      }

      console.log("[CiriumRatingsService] No ratings found");
      return null;
    } catch (error: any) {
      console.error("[CiriumRatingsService] Error fetching ratings:", error.message);
      return null;
    }
  }

  /**
   * Get performance ratings for a route (all flights between two airports)
   */
  async getRouteRatings(
    departureAirport: string,
    arrivalAirport: string
  ): Promise<FlightRating[]> {
    try {
      const url = `${this.baseUrl}/route/${departureAirport}/${arrivalAirport}`;
      const params = {
        appId: this.appId,
        appKey: this.appKey,
      };

      console.log(`[CiriumRatingsService] Fetching route ratings for ${departureAirport}-${arrivalAirport}`);

      const response = await axios.get<RatingsResponse>(url, { params });

      if (response.data.ratings) {
        console.log(`[CiriumRatingsService] Found ${response.data.ratings.length} route ratings`);
        return response.data.ratings;
      }

      return [];
    } catch (error: any) {
      console.error("[CiriumRatingsService] Error fetching route ratings:", error.message);
      return [];
    }
  }

  /**
   * Format ratings data for storage in Firestore
   */
  formatForStorage(rating: FlightRating): Record<string, any> {
    return {
      observations: rating.observations,
      ontimePercent: Math.round(rating.ontimePercent * 100),
      late15: rating.late15,
      late30: rating.late30,
      late45: rating.late45,
      cancelled: rating.cancelled,
      diverted: rating.diverted,
      delayMean: Math.round(rating.delayMean),
      delayMax: rating.delayMax,
      stars: rating.allStars,
      fetchedAt: new Date().toISOString(),
    };
  }
}
