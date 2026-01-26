"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.CiriumEquipmentService = void 0;
const axios_1 = __importDefault(require("axios"));
class CiriumEquipmentService {
    constructor() {
        this.baseUrl = "https://api.flightstats.com/flex/equipment/rest/v1/json";
        this.appId = process.env.CIRIUM_APP_ID || "";
        this.appKey = process.env.CIRIUM_APP_KEY || "";
    }
    /**
     * Get equipment details by IATA code
     */
    async getEquipment(iataCode) {
        try {
            const url = `${this.baseUrl}/iata/${iataCode}`;
            const params = {
                appId: this.appId,
                appKey: this.appKey,
            };
            console.log(`[CiriumEquipmentService] Fetching equipment for ${iataCode}`);
            const response = await axios_1.default.get(url, { params });
            if (response.data.equipment && response.data.equipment.length > 0) {
                const equipment = response.data.equipment[0];
                console.log(`[CiriumEquipmentService] Found: ${equipment.name}`);
                return equipment;
            }
            console.log("[CiriumEquipmentService] No equipment found");
            return null;
        }
        catch (error) {
            console.error("[CiriumEquipmentService] Error fetching equipment:", error.message);
            return null;
        }
    }
    /**
     * Format equipment for Firestore storage
     */
    formatForStorage(equipment) {
        // Generate a friendly description
        let type = "Aircraft";
        if (equipment.widebody && equipment.jet) {
            type = "Wide-body Jet";
        }
        else if (equipment.jet && !equipment.regional) {
            type = "Narrow-body Jet";
        }
        else if (equipment.jet && equipment.regional) {
            type = "Regional Jet";
        }
        else if (equipment.turboProp) {
            type = "Turboprop";
        }
        return {
            iataCode: equipment.iata,
            name: equipment.name,
            type,
            isJet: equipment.jet,
            isWidebody: equipment.widebody,
            isTurboProp: equipment.turboProp,
            isRegional: equipment.regional,
            fetchedAt: new Date().toISOString(),
        };
    }
}
exports.CiriumEquipmentService = CiriumEquipmentService;
//# sourceMappingURL=ciriumEquipmentService.js.map