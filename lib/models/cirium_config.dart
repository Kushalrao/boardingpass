/// Cirium API Configuration
class CiriumConfig {
  static const String appId = '5aae456b';
  static const String appKey = 'b5da0595ab863d6421f5e66b73805e0b';
  static const String baseUrl = 'https://api.flightstats.com/flex';

  /// Flight Status API base URL
  static const String flightStatusBaseUrl = '$baseUrl/flightstatus/rest/v2/json';

  /// Schedules API base URL
  static const String schedulesBaseUrl = '$baseUrl/schedules/rest/v1/json';

  /// Build query parameters with authentication
  static Map<String, String> get authParams => {
        'appId': appId,
        'appKey': appKey,
      };
}
