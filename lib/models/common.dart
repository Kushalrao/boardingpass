class Airline {
  final String fs;
  final String? iata;
  final String? icao;
  final String name;
  final bool active;
  final String? category;

  Airline({
    required this.fs,
    this.iata,
    this.icao,
    required this.name,
    required this.active,
    this.category,
  });

  factory Airline.fromJson(Map<String, dynamic> json) {
    return Airline(
      fs: json['fs'] ?? '',
      iata: json['iata'],
      icao: json['icao'],
      name: json['name'] ?? '',
      active: json['active'] ?? false,
      category: json['category'],
    );
  }

  Map<String, dynamic> toJson() => {
        'fs': fs,
        'iata': iata,
        'icao': icao,
        'name': name,
        'active': active,
        'category': category,
      };
}

class Airport {
  final String fs;
  final String? iata;
  final String? icao;
  final String name;
  final String city;
  final String? cityCode;
  final String countryCode;
  final String countryName;
  final String regionName;
  final String timeZoneRegionName;
  final double utcOffsetHours;
  final double latitude;
  final double longitude;
  final int? elevationFeet;
  final int? classification;
  final bool active;

  Airport({
    required this.fs,
    this.iata,
    this.icao,
    required this.name,
    required this.city,
    this.cityCode,
    required this.countryCode,
    required this.countryName,
    required this.regionName,
    required this.timeZoneRegionName,
    required this.utcOffsetHours,
    required this.latitude,
    required this.longitude,
    this.elevationFeet,
    this.classification,
    required this.active,
  });

  factory Airport.fromJson(Map<String, dynamic> json) {
    return Airport(
      fs: json['fs'] ?? '',
      iata: json['iata'],
      icao: json['icao'],
      name: json['name'] ?? '',
      city: json['city'] ?? '',
      cityCode: json['cityCode'],
      countryCode: json['countryCode'] ?? '',
      countryName: json['countryName'] ?? '',
      regionName: json['regionName'] ?? '',
      timeZoneRegionName: json['timeZoneRegionName'] ?? '',
      utcOffsetHours: (json['utcOffsetHours'] ?? 0).toDouble(),
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      elevationFeet: json['elevationFeet'],
      classification: json['classification'],
      active: json['active'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'fs': fs,
        'iata': iata,
        'icao': icao,
        'name': name,
        'city': city,
        'cityCode': cityCode,
        'countryCode': countryCode,
        'countryName': countryName,
        'regionName': regionName,
        'timeZoneRegionName': timeZoneRegionName,
        'utcOffsetHours': utcOffsetHours,
        'latitude': latitude,
        'longitude': longitude,
        'elevationFeet': elevationFeet,
        'classification': classification,
        'active': active,
      };
}

class Equipment {
  final String iata;
  final String name;
  final bool turboProp;
  final bool jet;
  final bool widebody;
  final bool regional;

  Equipment({
    required this.iata,
    required this.name,
    required this.turboProp,
    required this.jet,
    required this.widebody,
    required this.regional,
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      iata: json['iata'] ?? '',
      name: json['name'] ?? '',
      turboProp: json['turboProp'] ?? false,
      jet: json['jet'] ?? false,
      widebody: json['widebody'] ?? false,
      regional: json['regional'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'iata': iata,
        'name': name,
        'turboProp': turboProp,
        'jet': jet,
        'widebody': widebody,
        'regional': regional,
      };
}

class Codeshare {
  final String fsCode;
  final String flightNumber;
  final String? relationship;
  final String? serviceType;
  final List<String>? serviceClasses;
  final List<String>? trafficRestrictions;

  Codeshare({
    required this.fsCode,
    required this.flightNumber,
    this.relationship,
    this.serviceType,
    this.serviceClasses,
    this.trafficRestrictions,
  });

  factory Codeshare.fromJson(Map<String, dynamic> json) {
    return Codeshare(
      fsCode: json['fsCode'] ?? json['carrierFsCode'] ?? '',
      flightNumber: json['flightNumber'] ?? '',
      relationship: json['relationship'],
      serviceType: json['serviceType'],
      serviceClasses: json['serviceClasses'] != null
          ? List<String>.from(json['serviceClasses'])
          : null,
      trafficRestrictions: json['trafficRestrictions'] != null
          ? List<String>.from(json['trafficRestrictions'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'fsCode': fsCode,
        'flightNumber': flightNumber,
        'relationship': relationship,
        'serviceType': serviceType,
        'serviceClasses': serviceClasses,
        'trafficRestrictions': trafficRestrictions,
      };
}

class FlightDate {
  final String? dateUtc;
  final String? dateLocal;

  FlightDate({
    this.dateUtc,
    this.dateLocal,
  });

  factory FlightDate.fromJson(Map<String, dynamic> json) {
    return FlightDate(
      dateUtc: json['dateUtc'],
      dateLocal: json['dateLocal'],
    );
  }

  Map<String, dynamic> toJson() => {
        'dateUtc': dateUtc,
        'dateLocal': dateLocal,
      };

  DateTime? get utcDateTime =>
      dateUtc != null ? DateTime.tryParse(dateUtc!) : null;
  DateTime? get localDateTime =>
      dateLocal != null ? DateTime.tryParse(dateLocal!) : null;
}

class Appendix {
  final List<Airline> airlines;
  final List<Airport> airports;
  final List<Equipment> equipments;

  Appendix({
    required this.airlines,
    required this.airports,
    required this.equipments,
  });

  factory Appendix.fromJson(Map<String, dynamic> json) {
    return Appendix(
      airlines: (json['airlines'] as List<dynamic>?)
              ?.map((e) => Airline.fromJson(e))
              .toList() ??
          [],
      airports: (json['airports'] as List<dynamic>?)
              ?.map((e) => Airport.fromJson(e))
              .toList() ??
          [],
      equipments: (json['equipments'] as List<dynamic>?)
              ?.map((e) => Equipment.fromJson(e))
              .toList() ??
          [],
    );
  }

  /// Get airline by FS code
  Airline? getAirline(String fsCode) {
    try {
      return airlines.firstWhere((a) => a.fs == fsCode);
    } catch (_) {
      return null;
    }
  }

  /// Get airport by FS code
  Airport? getAirport(String fsCode) {
    try {
      return airports.firstWhere((a) => a.fs == fsCode);
    } catch (_) {
      return null;
    }
  }

  /// Get equipment by IATA code
  Equipment? getEquipment(String iataCode) {
    try {
      return equipments.firstWhere((e) => e.iata == iataCode);
    } catch (_) {
      return null;
    }
  }
}
