import axios from "axios";

interface FlightStatus {
  flightId: number;
  carrierFsCode: string;
  flightNumber: string;
  departureAirportFsCode: string;
  arrivalAirportFsCode: string;
  departureDate: { dateLocal: string; dateUtc: string };
  arrivalDate: { dateLocal: string; dateUtc: string };
  status: string;
  schedule: {
    flightType: string;
    serviceClasses: string;
    restrictions: string;
  };
  operationalTimes: {
    publishedDeparture?: { dateLocal: string; dateUtc: string };
    publishedArrival?: { dateLocal: string; dateUtc: string };
    scheduledGateDeparture?: { dateLocal: string; dateUtc: string };
    estimatedGateDeparture?: { dateLocal: string; dateUtc: string };
    actualGateDeparture?: { dateLocal: string; dateUtc: string };
    scheduledGateArrival?: { dateLocal: string; dateUtc: string };
    estimatedGateArrival?: { dateLocal: string; dateUtc: string };
    actualGateArrival?: { dateLocal: string; dateUtc: string };
    estimatedRunwayDeparture?: { dateLocal: string; dateUtc: string };
    actualRunwayDeparture?: { dateLocal: string; dateUtc: string };
    estimatedRunwayArrival?: { dateLocal: string; dateUtc: string };
    actualRunwayArrival?: { dateLocal: string; dateUtc: string };
  };
  codeshares?: Array<{ fsCode: string; flightNumber: string; relationship: string }>;
  delays?: {
    departureGateDelayMinutes?: number;
    arrivalGateDelayMinutes?: number;
  };
  flightDurations?: {
    scheduledBlockMinutes?: number;
    scheduledAirMinutes?: number;
    scheduledTaxiOutMinutes?: number;
    scheduledTaxiInMinutes?: number;
  };
  airportResources?: {
    departureTerminal?: string;
    departureGate?: string;
    arrivalTerminal?: string;
    arrivalGate?: string;
    baggage?: string;
  };
  flightEquipment?: {
    scheduledEquipmentIataCode?: string;
    actualEquipmentIataCode?: string;
    tailNumber?: string;
  };
}

interface FlightStatusResponse {
  flightStatuses: FlightStatus[];
  appendix: {
    airlines: Array<{ fs: string; name: string; iata: string; icao: string }>;
    airports: Array<{ fs: string; name: string; city: string; countryCode: string; latitude: number; longitude: number; utcOffsetHours: number }>;
    equipments: Array<{ iata: string; name: string; widebody: boolean }>;
  };
}

export class CiriumFlightStatusService {
  private appId: string;
  private appKey: string;
  private baseUrl = "https://api.flightstats.com/flex/flightstatus/rest/v2/json";

  constructor() {
    this.appId = process.env.CIRIUM_APP_ID || "";
    this.appKey = process.env.CIRIUM_APP_KEY || "";
  }

  /**
   * Get flight status by carrier, flight number, and departure date
   */
  async getFlightStatus(
    carrier: string,
    flightNumber: string,
    year: number,
    month: number,
    day: number
  ): Promise<{ status: FlightStatus; appendix: FlightStatusResponse['appendix'] } | null> {
    try {
      const url = `${this.baseUrl}/flight/status/${carrier}/${flightNumber}/dep/${year}/${month}/${day}`;
      const params = {
        appId: this.appId,
        appKey: this.appKey,
      };

      console.log(`[CiriumFlightStatusService] Fetching status for ${carrier}${flightNumber} on ${year}-${month}-${day}`);

      const response = await axios.get<FlightStatusResponse>(url, { params });

      if (response.data.flightStatuses && response.data.flightStatuses.length > 0) {
        const status = response.data.flightStatuses[0];
        console.log(`[CiriumFlightStatusService] Found status: ${status.status}`);
        return { status, appendix: response.data.appendix };
      }

      console.log("[CiriumFlightStatusService] No flight status found");
      return null;
    } catch (error: any) {
      console.error("[CiriumFlightStatusService] Error fetching status:", error.message);
      return null;
    }
  }

  /**
   * Format flight status for Firestore storage
   */
  formatForStorage(status: FlightStatus, appendix: FlightStatusResponse['appendix']): Record<string, any> {
    // Find airline name from appendix
    const airline = appendix.airlines?.find(a => a.fs === status.carrierFsCode);

    // Find equipment name from appendix
    const equipmentCode = status.flightEquipment?.actualEquipmentIataCode || status.flightEquipment?.scheduledEquipmentIataCode;
    const equipment = appendix.equipments?.find(e => e.iata === equipmentCode);

    return {
      status: status.status,
      airlineName: airline?.name || null,
      departureTerminal: status.airportResources?.departureTerminal || null,
      departureGate: status.airportResources?.departureGate || null,
      arrivalTerminal: status.airportResources?.arrivalTerminal || null,
      arrivalGate: status.airportResources?.arrivalGate || null,
      baggageBelt: status.airportResources?.baggage || null,
      scheduledDeparture: status.operationalTimes?.scheduledGateDeparture?.dateLocal || null,
      estimatedDeparture: status.operationalTimes?.estimatedGateDeparture?.dateLocal || null,
      actualDeparture: status.operationalTimes?.actualGateDeparture?.dateLocal || null,
      scheduledArrival: status.operationalTimes?.scheduledGateArrival?.dateLocal || null,
      estimatedArrival: status.operationalTimes?.estimatedGateArrival?.dateLocal || null,
      actualArrival: status.operationalTimes?.actualGateArrival?.dateLocal || null,
      departureDelayMinutes: status.delays?.departureGateDelayMinutes || null,
      arrivalDelayMinutes: status.delays?.arrivalGateDelayMinutes || null,
      flightDurationMinutes: status.flightDurations?.scheduledBlockMinutes || null,
      equipmentCode: equipmentCode || null,
      equipmentName: equipment?.name || null,
      isWidebody: equipment?.widebody || null,
      tailNumber: status.flightEquipment?.tailNumber || null,
      codeshares: status.codeshares?.map(c => `${c.fsCode}${c.flightNumber}`) || [],
      fetchedAt: new Date().toISOString(),
    };
  }
}
