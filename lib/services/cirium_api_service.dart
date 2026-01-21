import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cirium_config.dart';
import '../models/flight_status.dart';
import '../models/schedule.dart';

/// Cirium API Service for Flight Status and Schedule APIs
class CiriumApiService {
  final http.Client _client;

  CiriumApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Build URL with query parameters including authentication
  Uri _buildUrl(String baseUrl, String path, [Map<String, String>? params]) {
    final queryParams = {...CiriumConfig.authParams, ...?params};
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
  }

  /// Make HTTP GET request and return parsed JSON
  Future<Map<String, dynamic>> _get(Uri url) async {
    try {
      final response = await _client.get(url, headers: {
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        return {
          'error': {
            'httpStatusCode': response.statusCode,
            'errorMessage': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          }
        };
      }
    } catch (e) {
      return {
        'error': {
          'httpStatusCode': 0,
          'errorMessage': 'Network error: $e',
        }
      };
    }
  }

  // ============================================================
  // FLIGHT STATUS API (Track API)
  // ============================================================

  /// Get flight status by flight number and date
  ///
  /// [carrier] - Airline code (e.g., "LX")
  /// [flightNumber] - Flight number (e.g., "147")
  /// [year], [month], [day] - Departure date
  /// [extendedOptions] - Optional extended options (e.g., "includeNewFields")
  Future<FlightStatusResponse> getFlightStatus({
    required String carrier,
    required String flightNumber,
    required int year,
    required int month,
    required int day,
    String? extendedOptions,
  }) async {
    final path = '/flight/status/$carrier/$flightNumber/dep/$year/$month/$day';
    final params = <String, String>{};
    if (extendedOptions != null) {
      params['extendedOptions'] = extendedOptions;
    }

    final url = _buildUrl(CiriumConfig.flightStatusBaseUrl, path, params);
    final jsonResponse = await _get(url);
    return FlightStatusResponse.fromJson(jsonResponse);
  }

  /// Get flight status by flight number for today
  Future<FlightStatusResponse> getFlightStatusToday({
    required String carrier,
    required String flightNumber,
    String? extendedOptions,
  }) async {
    final now = DateTime.now();
    return getFlightStatus(
      carrier: carrier,
      flightNumber: flightNumber,
      year: now.year,
      month: now.month,
      day: now.day,
      extendedOptions: extendedOptions,
    );
  }

  /// Get flight status by route (airport to airport)
  ///
  /// [departureAirport] - Departure airport code (e.g., "DEL")
  /// [arrivalAirport] - Arrival airport code (e.g., "ZRH")
  /// [year], [month], [day] - Departure date
  /// [numHours] - Number of hours to search (default: 24)
  /// [maxFlights] - Maximum number of flights to return
  Future<FlightStatusResponse> getFlightStatusByRoute({
    required String departureAirport,
    required String arrivalAirport,
    required int year,
    required int month,
    required int day,
    int? numHours,
    int? maxFlights,
  }) async {
    final path = '/route/status/$departureAirport/$arrivalAirport/dep/$year/$month/$day';
    final params = <String, String>{};
    if (numHours != null) {
      params['numHours'] = numHours.toString();
    }
    if (maxFlights != null) {
      params['maxFlights'] = maxFlights.toString();
    }

    final url = _buildUrl(CiriumConfig.flightStatusBaseUrl, path, params);
    final jsonResponse = await _get(url);
    return FlightStatusResponse.fromJson(jsonResponse);
  }

  /// Get flight status by route for today
  Future<FlightStatusResponse> getFlightStatusByRouteToday({
    required String departureAirport,
    required String arrivalAirport,
    int? numHours,
    int? maxFlights,
  }) async {
    final now = DateTime.now();
    return getFlightStatusByRoute(
      departureAirport: departureAirport,
      arrivalAirport: arrivalAirport,
      year: now.year,
      month: now.month,
      day: now.day,
      numHours: numHours,
      maxFlights: maxFlights,
    );
  }

  // ============================================================
  // SCHEDULES API
  // ============================================================

  /// Get flight schedule by flight number and date
  ///
  /// [carrier] - Airline code (e.g., "AF")
  /// [flightNumber] - Flight number (e.g., "217")
  /// [year], [month], [day] - Departure date
  Future<ScheduleResponse> getSchedule({
    required String carrier,
    required String flightNumber,
    required int year,
    required int month,
    required int day,
  }) async {
    final path = '/flight/$carrier/$flightNumber/departing/$year/$month/$day';
    final url = _buildUrl(CiriumConfig.schedulesBaseUrl, path);
    final jsonResponse = await _get(url);
    return ScheduleResponse.fromJson(jsonResponse);
  }

  /// Get flight schedule by route (airport to airport)
  ///
  /// [departureAirport] - Departure airport code
  /// [arrivalAirport] - Arrival airport code
  /// [year], [month], [day] - Departure date
  Future<ScheduleResponse> getScheduleByRoute({
    required String departureAirport,
    required String arrivalAirport,
    required int year,
    required int month,
    required int day,
  }) async {
    final path = '/from/$departureAirport/to/$arrivalAirport/departing/$year/$month/$day';
    final url = _buildUrl(CiriumConfig.schedulesBaseUrl, path);
    final jsonResponse = await _get(url);
    return ScheduleResponse.fromJson(jsonResponse);
  }

  /// Get all scheduled flights departing from an airport on a date
  Future<ScheduleResponse> getScheduleByDepartureAirport({
    required String airport,
    required int year,
    required int month,
    required int day,
  }) async {
    final path = '/from/$airport/departing/$year/$month/$day';
    final url = _buildUrl(CiriumConfig.schedulesBaseUrl, path);
    final jsonResponse = await _get(url);
    return ScheduleResponse.fromJson(jsonResponse);
  }

  /// Get all scheduled flights arriving at an airport on a date
  Future<ScheduleResponse> getScheduleByArrivalAirport({
    required String airport,
    required int year,
    required int month,
    required int day,
  }) async {
    final path = '/to/$airport/arriving/$year/$month/$day';
    final url = _buildUrl(CiriumConfig.schedulesBaseUrl, path);
    final jsonResponse = await _get(url);
    return ScheduleResponse.fromJson(jsonResponse);
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================

  /// Parse flight identifier (e.g., "LX147" -> carrier: "LX", number: "147")
  static ({String carrier, String number}) parseFlightNumber(String flight) {
    // Match 2-3 letter carrier code followed by numbers
    final regex = RegExp(r'^([A-Z]{2,3})(\d+)$', caseSensitive: false);
    final match = regex.firstMatch(flight.toUpperCase().replaceAll(' ', ''));

    if (match != null) {
      return (carrier: match.group(1)!, number: match.group(2)!);
    }

    throw FormatException('Invalid flight number format: $flight');
  }

  /// Get flight status with automatic parsing of flight number
  Future<FlightStatusResponse> getFlightStatusByFlightNumber({
    required String flight,
    required int year,
    required int month,
    required int day,
    String? extendedOptions,
  }) async {
    final parsed = parseFlightNumber(flight);
    return getFlightStatus(
      carrier: parsed.carrier,
      flightNumber: parsed.number,
      year: year,
      month: month,
      day: day,
      extendedOptions: extendedOptions,
    );
  }

  /// Get schedule with automatic parsing of flight number
  Future<ScheduleResponse> getScheduleByFlightNumber({
    required String flight,
    required int year,
    required int month,
    required int day,
  }) async {
    final parsed = parseFlightNumber(flight);
    return getSchedule(
      carrier: parsed.carrier,
      flightNumber: parsed.number,
      year: year,
      month: month,
      day: day,
    );
  }

  /// Dispose the HTTP client
  void dispose() {
    _client.close();
  }
}
