enum BookingType {
  flight,
  hotel,
  train,
  bus,
  event,
  attraction,
  visa,
  vacationRental;

  static BookingType fromString(String value) {
    switch (value) {
      case 'flight':
        return BookingType.flight;
      case 'hotel':
        return BookingType.hotel;
      case 'train':
        return BookingType.train;
      case 'bus':
        return BookingType.bus;
      case 'event':
        return BookingType.event;
      case 'attraction':
        return BookingType.attraction;
      case 'visa':
        return BookingType.visa;
      case 'vacation_rental':
        return BookingType.vacationRental;
      default:
        return BookingType.flight;
    }
  }

  String toJson() {
    switch (this) {
      case BookingType.vacationRental:
        return 'vacation_rental';
      default:
        return name;
    }
  }
}

class Amount {
  final double? amount;
  final String? currency;

  Amount({this.amount, this.currency});

  factory Amount.fromJson(Map<String, dynamic>? json) {
    if (json == null) return Amount();
    return Amount(
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency,
      };
}

class ContactInformation {
  final String? email;
  final String? phone;

  ContactInformation({this.email, this.phone});

  factory ContactInformation.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ContactInformation();
    return ContactInformation(
      email: json['email'] as String?,
      phone: json['phone'] as String?,
    );
  }
}

class Address {
  final String? street;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;

  Address({this.street, this.city, this.state, this.country, this.postalCode});

  factory Address.fromJson(Map<String, dynamic>? json) {
    if (json == null) return Address();
    return Address(
      street: json['street'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      postalCode: json['postal_code'] as String?,
    );
  }
}

class Passenger {
  final String? name;
  final String? type;
  final String? ticketNumber;
  final String? seatNumber;
  final int? age;
  final String? gender;

  Passenger({
    this.name,
    this.type,
    this.ticketNumber,
    this.seatNumber,
    this.age,
    this.gender,
  });

  factory Passenger.fromJson(Map<String, dynamic> json) {
    return Passenger(
      name: json['name'] as String?,
      type: json['type'] as String?,
      ticketNumber: json['ticket_number'] as String?,
      seatNumber: json['seat_number'] as String?,
      age: json['age'] as int?,
      gender: json['gender'] as String?,
    );
  }
}

class FlightLocation {
  final String? city;
  final String? airport;
  final String? airportCode;
  final String? terminal;
  final String? datetime;
  final double? latitude;
  final double? longitude;

  FlightLocation({
    this.city,
    this.airport,
    this.airportCode,
    this.terminal,
    this.datetime,
    this.latitude,
    this.longitude,
  });

  factory FlightLocation.fromJson(Map<String, dynamic>? json) {
    if (json == null) return FlightLocation();
    return FlightLocation(
      city: json['city'] as String?,
      airport: json['airport'] as String?,
      airportCode: json['airport_code'] as String?,
      terminal: json['terminal'] as String?,
      datetime: json['datetime'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

class FlightSegment {
  final String? flightNumber;
  final String? airline;
  final String? operatedBy;
  final FlightLocation departure;
  final FlightLocation arrival;
  final String? flightClass;
  final String? fareType;
  final String? duration;
  final Map<String, String?>? baggageAllowance;

  FlightSegment({
    this.flightNumber,
    this.airline,
    this.operatedBy,
    required this.departure,
    required this.arrival,
    this.flightClass,
    this.fareType,
    this.duration,
    this.baggageAllowance,
  });

  factory FlightSegment.fromJson(Map<String, dynamic> json) {
    return FlightSegment(
      flightNumber: json['flight_number'] as String?,
      airline: json['airline'] as String?,
      operatedBy: json['operated_by'] as String?,
      departure: FlightLocation.fromJson(json['departure'] as Map<String, dynamic>?),
      arrival: FlightLocation.fromJson(json['arrival'] as Map<String, dynamic>?),
      flightClass: json['class'] as String?,
      fareType: json['fare_type'] as String?,
      duration: json['duration'] as String?,
      baggageAllowance: json['baggage_allowance'] != null
          ? Map<String, String?>.from(json['baggage_allowance'])
          : null,
    );
  }
}

class FareBreakdown {
  final Amount? baseFare;
  final Amount? taxes;
  final Amount? fees;
  final Amount? discounts;
  final Amount total;

  FareBreakdown({
    this.baseFare,
    this.taxes,
    this.fees,
    this.discounts,
    required this.total,
  });

  factory FareBreakdown.fromJson(Map<String, dynamic>? json) {
    if (json == null) return FareBreakdown(total: Amount());
    return FareBreakdown(
      baseFare: Amount.fromJson(json['base_fare'] as Map<String, dynamic>?),
      taxes: Amount.fromJson(json['taxes'] as Map<String, dynamic>?),
      fees: Amount.fromJson(json['fees'] as Map<String, dynamic>?),
      discounts: Amount.fromJson(json['discounts'] as Map<String, dynamic>?),
      total: Amount.fromJson(json['total'] as Map<String, dynamic>?),
    );
  }
}
