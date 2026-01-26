import axios from "axios";

interface WeatherConditions {
  wind?: {
    direction: number;
    directionIsVariable: boolean;
    speedKnots: string;
    gustSpeedKnots?: string;
  };
  visibility?: {
    miles: string;
    lessThan: boolean;
    cavok: boolean;
  };
  skyConditions?: Array<{
    coverage: string;
    baseHeightFeet?: number;
    cloudType?: string;
  }>;
  weatherConditions?: Array<{
    phenomenon: string;
    intensity: string;
  }>;
  pressureInchesHg?: string;
}

interface Metar {
  reportTime: string;
  report: string;
  weatherStationIcao: string;
  conditions: WeatherConditions;
  temperatureCelsius: string;
  dewPointCelsius: string;
  tags?: Array<{ key: string; value: string }>;
}

interface TafForecast {
  timePeriod?: { dateFrom: string; dateTo: string };
  conditions?: WeatherConditions;
}

interface Taf {
  report: string;
  forecasts?: TafForecast[];
}

interface WeatherResponse {
  metar?: Metar;
  taf?: Taf;
}

export class CiriumWeatherService {
  private appId: string;
  private appKey: string;
  private baseUrl = "https://api.flightstats.com/flex/weather/rest/v1/json";

  constructor() {
    this.appId = process.env.CIRIUM_APP_ID || "";
    this.appKey = process.env.CIRIUM_APP_KEY || "";
  }

  /**
   * Get weather for an airport
   */
  async getAirportWeather(airportCode: string): Promise<WeatherResponse | null> {
    try {
      const url = `${this.baseUrl}/all/${airportCode}`;
      const params = {
        appId: this.appId,
        appKey: this.appKey,
      };

      console.log(`[CiriumWeatherService] Fetching weather for ${airportCode}`);

      const response = await axios.get<WeatherResponse>(url, { params });

      if (response.data.metar || response.data.taf) {
        console.log(`[CiriumWeatherService] Found weather data for ${airportCode}`);
        return response.data;
      }

      console.log("[CiriumWeatherService] No weather data found");
      return null;
    } catch (error: any) {
      console.error("[CiriumWeatherService] Error fetching weather:", error.message);
      return null;
    }
  }

  /**
   * Format weather for Firestore storage
   */
  formatForStorage(weather: WeatherResponse, airportCode: string): Record<string, any> {
    const metar = weather.metar;
    const conditions = metar?.conditions;

    // Parse sky conditions
    let skyCondition = "Unknown";
    if (conditions?.skyConditions && conditions.skyConditions.length > 0) {
      const coverage = conditions.skyConditions[0].coverage;
      if (coverage === "CLR" || coverage === "SKC" || coverage === "No significant clouds") {
        skyCondition = "Clear";
      } else if (coverage === "FEW") {
        skyCondition = "Few clouds";
      } else if (coverage === "SCT") {
        skyCondition = "Scattered clouds";
      } else if (coverage === "BKN") {
        skyCondition = "Broken clouds";
      } else if (coverage === "OVC") {
        skyCondition = "Overcast";
      } else {
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
