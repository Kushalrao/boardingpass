"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.CiriumFlightStatusService = void 0;
const axios_1 = __importDefault(require("axios"));
class CiriumFlightStatusService {
    constructor() {
        this.baseUrl = "https://api.flightstats.com/flex/flightstatus/rest/v2/json";
        this.appId = process.env.CIRIUM_APP_ID || "";
        this.appKey = process.env.CIRIUM_APP_KEY || "";
    }
    /**
     * Get flight status by carrier, flight number, and departure date
     */
    async getFlightStatus(carrier, flightNumber, year, month, day) {
        try {
            const url = `${this.baseUrl}/flight/status/${carrier}/${flightNumber}/dep/${year}/${month}/${day}`;
            const params = {
                appId: this.appId,
                appKey: this.appKey,
            };
            console.log(`[CiriumFlightStatusService] Fetching status for ${carrier}${flightNumber} on ${year}-${month}-${day}`);
            const response = await axios_1.default.get(url, { params });
            if (response.data.flightStatuses && response.data.flightStatuses.length > 0) {
                const status = response.data.flightStatuses[0];
                console.log(`[CiriumFlightStatusService] Found status: ${status.status}`);
                return { status, appendix: response.data.appendix };
            }
            console.log("[CiriumFlightStatusService] No flight status found");
            return null;
        }
        catch (error) {
            console.error("[CiriumFlightStatusService] Error fetching status:", error.message);
            return null;
        }
    }
    /**
     * Format flight status for Firestore storage
     */
    formatForStorage(status, appendix) {
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
exports.CiriumFlightStatusService = CiriumFlightStatusService;
//# sourceMappingURL=ciriumFlightStatusService.js.map