import 'common.dart';

/// Flight Status Response from Cirium API
class FlightStatusResponse {
  final FlightStatusRequest? request;
  final List<FlightStatus> flightStatuses;
  final Appendix? appendix;
  final ApiError? error;

  FlightStatusResponse({
    this.request,
    required this.flightStatuses,
    this.appendix,
    this.error,
  });

  factory FlightStatusResponse.fromJson(Map<String, dynamic> json) {
    return FlightStatusResponse(
      request: json['request'] != null
          ? FlightStatusRequest.fromJson(json['request'])
          : null,
      flightStatuses: (json['flightStatuses'] as List<dynamic>?)
              ?.map((e) => FlightStatus.fromJson(e))
              .toList() ??
          [],
      appendix:
          json['appendix'] != null ? Appendix.fromJson(json['appendix']) : null,
      error: json['error'] != null ? ApiError.fromJson(json['error']) : null,
    );
  }

  bool get hasError => error != null;
  bool get hasFlights => flightStatuses.isNotEmpty;
}

class FlightStatusRequest {
  final String? url;
  final Map<String, dynamic>? airline;
  final Map<String, dynamic>? flight;
  final Map<String, dynamic>? date;
  final Map<String, dynamic>? departureAirport;
  final Map<String, dynamic>? arrivalAirport;

  FlightStatusRequest({
    this.url,
    this.airline,
    this.flight,
    this.date,
    this.departureAirport,
    this.arrivalAirport,
  });

  factory FlightStatusRequest.fromJson(Map<String, dynamic> json) {
    return FlightStatusRequest(
      url: json['url'],
      airline: json['airline'],
      flight: json['flight'],
      date: json['date'],
      departureAirport: json['departureAirport'],
      arrivalAirport: json['arrivalAirport'],
    );
  }
}

class FlightStatus {
  final int? flightId;
  final String carrierFsCode;
  final String? operatingCarrierFsCode;
  final String flightNumber;
  final String departureAirportFsCode;
  final String arrivalAirportFsCode;
  final FlightDate? departureDate;
  final FlightDate? arrivalDate;
  final String status;
  final FlightScheduleInfo? schedule;
  final OperationalTimes? operationalTimes;
  final List<Codeshare> codeshares;
  final Delays? delays;
  final FlightDurations? flightDurations;
  final AirportResources? airportResources;
  final FlightEquipment? flightEquipment;
  final List<IrregularOperation>? irregularOperations;

  FlightStatus({
    this.flightId,
    required this.carrierFsCode,
    this.operatingCarrierFsCode,
    required this.flightNumber,
    required this.departureAirportFsCode,
    required this.arrivalAirportFsCode,
    this.departureDate,
    this.arrivalDate,
    required this.status,
    this.schedule,
    this.operationalTimes,
    required this.codeshares,
    this.delays,
    this.flightDurations,
    this.airportResources,
    this.flightEquipment,
    this.irregularOperations,
  });

  factory FlightStatus.fromJson(Map<String, dynamic> json) {
    return FlightStatus(
      flightId: json['flightId'],
      carrierFsCode: json['carrierFsCode'] ?? '',
      operatingCarrierFsCode: json['operatingCarrierFsCode'],
      flightNumber: json['flightNumber'] ?? '',
      departureAirportFsCode: json['departureAirportFsCode'] ?? '',
      arrivalAirportFsCode: json['arrivalAirportFsCode'] ?? '',
      departureDate: json['departureDate'] != null
          ? FlightDate.fromJson(json['departureDate'])
          : null,
      arrivalDate: json['arrivalDate'] != null
          ? FlightDate.fromJson(json['arrivalDate'])
          : null,
      status: json['status'] ?? 'U',
      schedule: json['schedule'] != null
          ? FlightScheduleInfo.fromJson(json['schedule'])
          : null,
      operationalTimes: json['operationalTimes'] != null
          ? OperationalTimes.fromJson(json['operationalTimes'])
          : null,
      codeshares: (json['codeshares'] as List<dynamic>?)
              ?.map((e) => Codeshare.fromJson(e))
              .toList() ??
          [],
      delays: json['delays'] != null ? Delays.fromJson(json['delays']) : null,
      flightDurations: json['flightDurations'] != null
          ? FlightDurations.fromJson(json['flightDurations'])
          : null,
      airportResources: json['airportResources'] != null
          ? AirportResources.fromJson(json['airportResources'])
          : null,
      flightEquipment: json['flightEquipment'] != null
          ? FlightEquipment.fromJson(json['flightEquipment'])
          : null,
      irregularOperations: (json['irregularOperations'] as List<dynamic>?)
          ?.map((e) => IrregularOperation.fromJson(e))
          .toList(),
    );
  }

  /// Get human-readable status
  String get statusText {
    switch (status) {
      case 'S':
        return 'Scheduled';
      case 'A':
        return 'Active';
      case 'L':
        return 'Landed';
      case 'C':
        return 'Cancelled';
      case 'D':
        return 'Diverted';
      case 'R':
        return 'Redirected';
      case 'U':
        return 'Unknown';
      case 'NO':
        return 'Not Operating';
      default:
        return status;
    }
  }

  /// Get full flight number (e.g., "LX147")
  String get fullFlightNumber => '$carrierFsCode$flightNumber';
}

class FlightScheduleInfo {
  final String? flightType;
  final String? serviceClasses;
  final String? restrictions;

  FlightScheduleInfo({
    this.flightType,
    this.serviceClasses,
    this.restrictions,
  });

  factory FlightScheduleInfo.fromJson(Map<String, dynamic> json) {
    return FlightScheduleInfo(
      flightType: json['flightType'],
      serviceClasses: json['serviceClasses'],
      restrictions: json['restrictions'],
    );
  }
}

class OperationalTimes {
  final FlightDate? publishedDeparture;
  final FlightDate? scheduledGateDeparture;
  final FlightDate? estimatedGateDeparture;
  final FlightDate? actualGateDeparture;
  final FlightDate? estimatedRunwayDeparture;
  final FlightDate? actualRunwayDeparture;
  final FlightDate? publishedArrival;
  final FlightDate? scheduledGateArrival;
  final FlightDate? estimatedGateArrival;
  final FlightDate? actualGateArrival;
  final FlightDate? estimatedRunwayArrival;
  final FlightDate? actualRunwayArrival;

  OperationalTimes({
    this.publishedDeparture,
    this.scheduledGateDeparture,
    this.estimatedGateDeparture,
    this.actualGateDeparture,
    this.estimatedRunwayDeparture,
    this.actualRunwayDeparture,
    this.publishedArrival,
    this.scheduledGateArrival,
    this.estimatedGateArrival,
    this.actualGateArrival,
    this.estimatedRunwayArrival,
    this.actualRunwayArrival,
  });

  factory OperationalTimes.fromJson(Map<String, dynamic> json) {
    return OperationalTimes(
      publishedDeparture: json['publishedDeparture'] != null
          ? FlightDate.fromJson(json['publishedDeparture'])
          : null,
      scheduledGateDeparture: json['scheduledGateDeparture'] != null
          ? FlightDate.fromJson(json['scheduledGateDeparture'])
          : null,
      estimatedGateDeparture: json['estimatedGateDeparture'] != null
          ? FlightDate.fromJson(json['estimatedGateDeparture'])
          : null,
      actualGateDeparture: json['actualGateDeparture'] != null
          ? FlightDate.fromJson(json['actualGateDeparture'])
          : null,
      estimatedRunwayDeparture: json['estimatedRunwayDeparture'] != null
          ? FlightDate.fromJson(json['estimatedRunwayDeparture'])
          : null,
      actualRunwayDeparture: json['actualRunwayDeparture'] != null
          ? FlightDate.fromJson(json['actualRunwayDeparture'])
          : null,
      publishedArrival: json['publishedArrival'] != null
          ? FlightDate.fromJson(json['publishedArrival'])
          : null,
      scheduledGateArrival: json['scheduledGateArrival'] != null
          ? FlightDate.fromJson(json['scheduledGateArrival'])
          : null,
      estimatedGateArrival: json['estimatedGateArrival'] != null
          ? FlightDate.fromJson(json['estimatedGateArrival'])
          : null,
      actualGateArrival: json['actualGateArrival'] != null
          ? FlightDate.fromJson(json['actualGateArrival'])
          : null,
      estimatedRunwayArrival: json['estimatedRunwayArrival'] != null
          ? FlightDate.fromJson(json['estimatedRunwayArrival'])
          : null,
      actualRunwayArrival: json['actualRunwayArrival'] != null
          ? FlightDate.fromJson(json['actualRunwayArrival'])
          : null,
    );
  }
}

class Delays {
  final int? departureGateDelayMinutes;
  final int? departureRunwayDelayMinutes;
  final int? arrivalGateDelayMinutes;
  final int? arrivalRunwayDelayMinutes;

  Delays({
    this.departureGateDelayMinutes,
    this.departureRunwayDelayMinutes,
    this.arrivalGateDelayMinutes,
    this.arrivalRunwayDelayMinutes,
  });

  factory Delays.fromJson(Map<String, dynamic> json) {
    return Delays(
      departureGateDelayMinutes: json['departureGateDelayMinutes'],
      departureRunwayDelayMinutes: json['departureRunwayDelayMinutes'],
      arrivalGateDelayMinutes: json['arrivalGateDelayMinutes'],
      arrivalRunwayDelayMinutes: json['arrivalRunwayDelayMinutes'],
    );
  }

  bool get hasDepartureDelay =>
      (departureGateDelayMinutes ?? 0) > 0 ||
      (departureRunwayDelayMinutes ?? 0) > 0;
  bool get hasArrivalDelay =>
      (arrivalGateDelayMinutes ?? 0) > 0 ||
      (arrivalRunwayDelayMinutes ?? 0) > 0;
}

class FlightDurations {
  final int? scheduledBlockMinutes;
  final int? blockMinutes;
  final int? airMinutes;
  final int? taxiOutMinutes;
  final int? taxiInMinutes;

  FlightDurations({
    this.scheduledBlockMinutes,
    this.blockMinutes,
    this.airMinutes,
    this.taxiOutMinutes,
    this.taxiInMinutes,
  });

  factory FlightDurations.fromJson(Map<String, dynamic> json) {
    return FlightDurations(
      scheduledBlockMinutes: json['scheduledBlockMinutes'],
      blockMinutes: json['blockMinutes'],
      airMinutes: json['airMinutes'],
      taxiOutMinutes: json['taxiOutMinutes'],
      taxiInMinutes: json['taxiInMinutes'],
    );
  }

  /// Get scheduled duration as Duration object
  Duration? get scheduledDuration => scheduledBlockMinutes != null
      ? Duration(minutes: scheduledBlockMinutes!)
      : null;

  /// Get actual duration as Duration object
  Duration? get actualDuration =>
      blockMinutes != null ? Duration(minutes: blockMinutes!) : null;
}

class AirportResources {
  final String? departureTerminal;
  final String? departureGate;
  final String? arrivalTerminal;
  final String? arrivalGate;
  final String? baggage;

  AirportResources({
    this.departureTerminal,
    this.departureGate,
    this.arrivalTerminal,
    this.arrivalGate,
    this.baggage,
  });

  factory AirportResources.fromJson(Map<String, dynamic> json) {
    return AirportResources(
      departureTerminal: json['departureTerminal'],
      departureGate: json['departureGate'],
      arrivalTerminal: json['arrivalTerminal'],
      arrivalGate: json['arrivalGate'],
      baggage: json['baggage'],
    );
  }
}

class FlightEquipment {
  final String? scheduledEquipmentIataCode;
  final String? actualEquipmentIataCode;
  final String? tailNumber;
  final int? fleetAircraftId;

  FlightEquipment({
    this.scheduledEquipmentIataCode,
    this.actualEquipmentIataCode,
    this.tailNumber,
    this.fleetAircraftId,
  });

  factory FlightEquipment.fromJson(Map<String, dynamic> json) {
    return FlightEquipment(
      scheduledEquipmentIataCode: json['scheduledEquipmentIataCode'],
      actualEquipmentIataCode: json['actualEquipmentIataCode'],
      tailNumber: json['tailNumber'],
      fleetAircraftId: json['fleetAircraftId'],
    );
  }
}

class IrregularOperation {
  final String? type;
  final String? newArrivalAirportFsCode;
  final String? dateUtc;
  final String? dateLocal;

  IrregularOperation({
    this.type,
    this.newArrivalAirportFsCode,
    this.dateUtc,
    this.dateLocal,
  });

  factory IrregularOperation.fromJson(Map<String, dynamic> json) {
    return IrregularOperation(
      type: json['type'],
      newArrivalAirportFsCode: json['newArrivalAirportFsCode'],
      dateUtc: json['dateUtc'],
      dateLocal: json['dateLocal'],
    );
  }
}

class ApiError {
  final int? httpStatusCode;
  final String? errorId;
  final String? errorMessage;

  ApiError({
    this.httpStatusCode,
    this.errorId,
    this.errorMessage,
  });

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      httpStatusCode: json['httpStatusCode'],
      errorId: json['errorId'],
      errorMessage: json['errorMessage'],
    );
  }

  @override
  String toString() =>
      'ApiError(code: $httpStatusCode, message: $errorMessage)';
}
