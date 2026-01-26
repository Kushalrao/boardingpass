import axios from "axios";

interface Equipment {
  iata: string;
  name: string;
  turboProp: boolean;
  jet: boolean;
  widebody: boolean;
  regional: boolean;
}

interface EquipmentResponse {
  equipment: Equipment[];
}

export class CiriumEquipmentService {
  private appId: string;
  private appKey: string;
  private baseUrl = "https://api.flightstats.com/flex/equipment/rest/v1/json";

  constructor() {
    this.appId = process.env.CIRIUM_APP_ID || "";
    this.appKey = process.env.CIRIUM_APP_KEY || "";
  }

  /**
   * Get equipment details by IATA code
   */
  async getEquipment(iataCode: string): Promise<Equipment | null> {
    try {
      const url = `${this.baseUrl}/iata/${iataCode}`;
      const params = {
        appId: this.appId,
        appKey: this.appKey,
      };

      console.log(`[CiriumEquipmentService] Fetching equipment for ${iataCode}`);

      const response = await axios.get<EquipmentResponse>(url, { params });

      if (response.data.equipment && response.data.equipment.length > 0) {
        const equipment = response.data.equipment[0];
        console.log(`[CiriumEquipmentService] Found: ${equipment.name}`);
        return equipment;
      }

      console.log("[CiriumEquipmentService] No equipment found");
      return null;
    } catch (error: any) {
      console.error("[CiriumEquipmentService] Error fetching equipment:", error.message);
      return null;
    }
  }

  /**
   * Format equipment for Firestore storage
   */
  formatForStorage(equipment: Equipment): Record<string, any> {
    // Generate a friendly description
    let type = "Aircraft";
    if (equipment.widebody && equipment.jet) {
      type = "Wide-body Jet";
    } else if (equipment.jet && !equipment.regional) {
      type = "Narrow-body Jet";
    } else if (equipment.jet && equipment.regional) {
      type = "Regional Jet";
    } else if (equipment.turboProp) {
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
