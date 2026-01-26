"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.CiriumWeatherService = void 0;
const axios_1 = __importDefault(require("axios"));
class CiriumWeatherService {
    constructor() {
        this.baseUrl = "https://api.flightstats.com/flex/weather/rest/v1/json";
        this.appId = process.env.CIRIUM_APP_ID || "";
        this.appKey = process.env.CIRIUM_APP_KEY || "";
    }
    /**
     * Get weather for an airport
     */
    async getAirportWeather(airportCode) {
        try {
            const url = `${this.baseUrl}/all/${airportCode}`;
            const params = {
                appId: this.appId,
                appKey: this.appKey,
            };
            console.log(`[CiriumWeatherService] Fetching weather for ${airportCode}`);
            const response = await axios_1.default.get(url, { params });
            if (response.data.metar || response.data.taf) {
                console.log(`[CiriumWeatherService] Found weather data for ${airportCode}`);
                return response.data;
            }
            console.log("[CiriumWeatherService] No weather data found");
            return null;
        }
        catch (error) {
            console.error("[CiriumWeatherService] Error fetching weather:", error.message);
            return null;
        }
    }
    /**
     * Format weather for Firestore storage
     */
    formatForStorage(weather, airportCode) {
        const metar = weather.metar;
        const conditions = metar?.conditions;
        // Parse sky conditions
        let skyCondition = "Unknown";
        if (conditions?.skyConditions && conditions.skyConditions.length > 0) {
            const coverage = conditions.skyConditions[0].coverage;
            if (coverage === "CLR" || coverage === "SKC" || coverage === "No significant clouds") {
                skyCondition = "Clear";
            }
            else if (coverage === "FEW") {
                skyCondition = "Few clouds";
            }
            else if (coverage === "SCT") {
                skyCondition = "Scattered clouds";
            }
            else if (coverage === "BKN") {
                skyCondition = "Broken clouds";
            }
            else if (coverage === "OVC") {
                skyCondition = "Overcast";
            }
            else {
                skyCondition = coverage;
            }
        }
        // Parse weather phenomena
        let weatherDescription = skyCondition;
        if (conditions?.weatherConditions && conditions.weatherConditions.length > 0) {
            const phenomena = conditions.weatherConditions.map(w => w.phenomenon).join(", ");
            weatherDescription = phenomena;
        }
        // Parse tags for simple description
        let simpleDescription = weatherDescription;
        if (metar?.tags && metar.tags.length > 0) {
            const prevailing = metar.tags.find(t => t.key === "Prevailing Conditions");
            if (prevailing) {
                simpleDescription = prevailing.value;
            }
        }
        return {
            airportCode,
            reportTime: metar?.reportTime || null,
            temperatureCelsius: metar?.temperatureCelsius ? parseFloat(metar.temperatureCelsius) : null,
            dewPointCelsius: metar?.dewPointCelsius ? parseFloat(metar.dewPointCelsius) : null,
            windDirection: conditions?.wind?.direction || null,
            windSpeedKnots: conditions?.wind?.speedKnots ? parseFloat(conditions.wind.speedKnots) : null,
            windGustKnots: conditions?.wind?.gustSpeedKnots ? parseFloat(conditions.wind.gustSpeedKnots) : null,
            visibilityMiles: conditions?.visibility?.miles ? parseFloat(conditions.visibility.miles) : null,
            pressureInchesHg: conditions?.pressureInchesHg ? parseFloat(conditions.pressureInchesHg) : null,
            skyCondition,
            weatherDescription: simpleDescription,
            rawMetar: metar?.report || null,
            fetchedAt: new Date().toISOString(),
        };
    }
}
exports.CiriumWeatherService = CiriumWeatherService;
//# sourceMappingURL=ciriumWeatherService.js.map