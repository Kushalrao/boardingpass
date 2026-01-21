import 'common.dart';
import 'flight_status.dart';

/// Schedule Response from Cirium API
class ScheduleResponse {
  final ScheduleRequest? request;
  final List<ScheduledFlight> scheduledFlights;
  final Appendix? appendix;
  final ApiError? error;

  ScheduleResponse({
    this.request,
    required this.scheduledFlights,
    this.appendix,
    this.error,
  });

  factory ScheduleResponse.fromJson(Map<String, dynamic> json) {
    return ScheduleResponse(
      request: json['request'] != null
          ? ScheduleRequest.fromJson(json['request'])
          : null,
      scheduledFlights: (json['scheduledFlights'] as List<dynamic>?)
              ?.map((e) => ScheduledFlight.fromJson(e))
              .toList() ??
          [],
      appendix:
          json['appendix'] != null ? Appendix.fromJson(json['appendix']) : null,
      error: json['error'] != null ? ApiError.fromJson(json['error']) : null,
    );
  }

  bool get hasError => error != null;
  bool get hasFlights => scheduledFlights.isNotEmpty;
}

class ScheduleRequest {
  final String? url;
  final Map<String, dynamic>? carrier;
  final Map<String, dynamic>? flightNumber;
  final Map<String, dynamic>? date;
  final bool? departing;

  ScheduleRequest({
    this.url,
    this.carrier,
    this.flightNumber,
    this.date,
    this.departing,
  });

  factory ScheduleRequest.fromJson(Map<String, dynamic> json) {
    return ScheduleRequest(
      url: json['url'],
      carrier: json['carrier'],
      flightNumber: json['flightNumber'],
      date: json['date'],
      departing: json['departing'],
    );
  }
}

class ScheduledFlight {
  final String carrierFsCode;
  final String flightNumber;
  final String departureAirportFsCode;
  final String arrivalAirportFsCode;
  final String departureTime;
  final String arrivalTime;
  final int stops;
  final String? departureTerminal;
  final String? arrivalTerminal;
  final String? flightEquipmentIataCode;
  final bool isCodeshare;
  final bool isWetlease;
  final String? serviceType;
  final List<String> serviceClasses;
  final List<String> trafficRestrictions;
  final List<Codeshare> codeshares;
  final String? referenceCode;

  ScheduledFlight({
    required this.carrierFsCode,
    required this.flightNumber,
    required this.departureAirportFsCode,
    required this.arrivalAirportFsCode,
    required this.departureTime,
    required this.arrivalTime,
    required this.stops,
    this.departureTerminal,
    this.arrivalTerminal,
    this.flightEquipmentIataCode,
    required this.isCodeshare,
    required this.isWetlease,
    this.serviceType,
    required this.serviceClasses,
    required this.trafficRestrictions,
    required this.codeshares,
    this.referenceCode,
  });

  factory ScheduledFlight.fromJson(Map<String, dynamic> json) {
    return ScheduledFlight(
      carrierFsCode: json['carrierFsCode'] ?? '',
      flightNumber: json['flightNumber'] ?? '',
      departureAirportFsCode: json['departureAirportFsCode'] ?? '',
      arrivalAirportFsCode: json['arrivalAirportFsCode'] ?? '',
      departureTime: json['departureTime'] ?? '',
      arrivalTime: json['arrivalTime'] ?? '',
      stops: json['stops'] ?? 0,
      departureTerminal: json['departureTerminal'],
      arrivalTerminal: json['arrivalTerminal'],
      flightEquipmentIataCode: json['flightEquipmentIataCode'],
      isCodeshare: json['isCodeshare'] ?? false,
      isWetlease: json['isWetlease'] ?? false,
      serviceType: json['serviceType'],
      serviceClasses: (json['serviceClasses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      trafficRestrictions: (json['trafficRestrictions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      codeshares: (json['codeshares'] as List<dynamic>?)
              ?.map((e) => Codeshare.fromJson(e))
              .toList() ??
          [],
      referenceCode: json['referenceCode'],
    );
  }

  /// Get full flight number (e.g., "AF217")
  String get fullFlightNumber => '$carrierFsCode$flightNumber';

  /// Parse departure time to DateTime
  DateTime? get departureDateTime => DateTime.tryParse(departureTime);

  /// Parse arrival time to DateTime
  DateTime? get arrivalDateTime => DateTime.tryParse(arrivalTime);

  /// Check if this is a non-stop flight
  bool get isNonStop => stops == 0;

  /// Get service type description
  String get serviceTypeDescription {
    switch (serviceType) {
      case 'J':
        return 'Scheduled Passenger';
      case 'F':
        return 'Scheduled Cargo';
      case 'G':
        return 'Charter Passenger';
      case 'H':
        return 'Charter Cargo';
      case 'P':
        return 'Positioning';
      default:
        return serviceType ?? 'Unknown';
    }
  }

  Map<String, dynamic> toJson() => {
        'carrierFsCode': carrierFsCode,
        'flightNumber': flightNumber,
        'departureAirportFsCode': departureAirportFsCode,
        'arrivalAirportFsCode': arrivalAirportFsCode,
        'departureTime': departureTime,
        'arrivalTime': arrivalTime,
        'stops': stops,
        'departureTerminal': departureTerminal,
        'arrivalTerminal': arrivalTerminal,
        'flightEquipmentIataCode': flightEquipmentIataCode,
        'isCodeshare': isCodeshare,
        'isWetlease': isWetlease,
        'serviceType': serviceType,
        'serviceClasses': serviceClasses,
        'trafficRestrictions': trafficRestrictions,
        'referenceCode': referenceCode,
      };
}
