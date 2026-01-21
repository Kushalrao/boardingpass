import 'booking_types.dart';

abstract class Booking {
  final BookingType bookingType;
  final String? bookingReference;
  final String? bookingDate;
  final String? status;
  final ContactInformation? contactInformation;
  final String? date;
  final String? pdfParseStatus;
  final String? pdfParseError;
  final String? origin;
  final String? destination;
  final double? amount;
  final String? currency;
  final double? amountINR;
  final String? emailMessageId;
  final String? confirmationNumber;

  Booking({
    required this.bookingType,
    this.bookingReference,
    this.bookingDate,
    this.status,
    this.contactInformation,
    this.date,
    this.pdfParseStatus,
    this.pdfParseError,
    this.origin,
    this.destination,
    this.amount,
    this.currency,
    this.amountINR,
    this.emailMessageId,
    this.confirmationNumber,
  });

  Map<String, dynamic> toJson() {
    return {
      'booking_type': bookingType.toJson(),
      'booking_reference': bookingReference,
      'booking_date': bookingDate,
      'status': status,
      'date': date,
      'pdfParseStatus': pdfParseStatus,
      'pdfParseError': pdfParseError,
      'origin': origin,
      'destination': destination,
      'amount': amount,
      'currency': currency,
      'amountINR': amountINR,
      'email_message_id': emailMessageId,
      'confirmation_number': confirmationNumber,
    };
  }

  factory Booking.fromJson(Map<String, dynamic> json) {
    final type = BookingType.fromString(json['booking_type'] as String? ?? 'flight');

    switch (type) {
      case BookingType.flight:
        return FlightBooking.fromJson(json);
      case BookingType.hotel:
        return HotelBooking.fromJson(json);
      case BookingType.train:
        return TrainBooking.fromJson(json);
      case BookingType.bus:
        return BusBooking.fromJson(json);
      case BookingType.event:
        return EventBooking.fromJson(json);
      case BookingType.attraction:
        return AttractionBooking.fromJson(json);
      case BookingType.visa:
        return VisaBooking.fromJson(json);
      case BookingType.vacationRental:
        return VacationRentalBooking.fromJson(json);
    }
  }
}

class FlightBooking extends Booking {
  final String? airline;
  final String? tripType;
  final Amount? totalAmountPaid;
  final List<Passenger> passengers;
  final List<FlightSegment> flights;
  final FareBreakdown? fareBreakdown;
  final String? additionalInfo;

  FlightBooking({
    super.bookingReference,
    super.bookingDate,
    super.status,
    super.contactInformation,
    super.date,
    super.pdfParseStatus,
    super.pdfParseError,
    super.origin,
    super.destination,
    super.amount,
    super.currency,
    super.amountINR,
    super.emailMessageId,
    super.confirmationNumber,
    this.airline,
    this.tripType,
    this.totalAmountPaid,
    this.passengers = const [],
    this.flights = const [],
    this.fareBreakdown,
    this.additionalInfo,
  }) : super(bookingType: BookingType.flight);

  factory FlightBooking.fromJson(Map<String, dynamic> json) {
    return FlightBooking(
      bookingReference: json['booking_reference'] as String?,
      bookingDate: json['booking_date'] as String?,
      status: json['status'] as String?,
      contactInformation: ContactInformation.fromJson(
          json['contact_information'] as Map<String, dynamic>?),
      date: json['date'] as String?,
      pdfParseStatus: json['pdfParseStatus'] as String?,
      pdfParseError: json['pdfParseError'] as String?,
      origin: json['origin'] as String?,
      destination: json['destination'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      amountINR: (json['amountINR'] as num?)?.toDouble(),
      emailMessageId: json['email_message_id'] as String?,
      confirmationNumber: json['confirmation_number'] as String?,
      airline: json['airline'] as String?,
      tripType: json['trip_type'] as String?,
      totalAmountPaid:
          Amount.fromJson(json['total_amount_paid'] as Map<String, dynamic>?),
      passengers: (json['passengers'] as List<dynamic>?)
              ?.map((e) => Passenger.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      flights: (json['flights'] as List<dynamic>?)
              ?.map((e) => FlightSegment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      fareBreakdown:
          FareBreakdown.fromJson(json['fare_breakdown'] as Map<String, dynamic>?),
      additionalInfo: json['additional_info'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'airline': airline,
      'trip_type': tripType,
      'total_amount_paid': totalAmountPaid?.toJson(),
      'additional_info': additionalInfo,
    };
  }
}

class HotelBooking extends Booking {
  final String? hotelName;
  final String? hotelBrand;
  final Address? address;
  final String? checkIn;
  final String? checkOut;
  final int? nights;
  final Map<String, dynamic>? roomDetails;
  final List<Passenger> guests;
  final Amount? totalAmount;
  final List<String> amenities;
  final String? cancellationPolicy;

  HotelBooking({
    super.bookingReference,
    super.bookingDate,
    super.status,
    super.contactInformation,
    super.date,
    super.pdfParseStatus,
    super.pdfParseError,
    super.origin,
    super.destination,
    super.amount,
    super.currency,
    super.amountINR,
    this.hotelName,
    this.hotelBrand,
    this.address,
    this.checkIn,
    this.checkOut,
    this.nights,
    this.roomDetails,
    this.guests = const [],
    this.totalAmount,
    this.amenities = const [],
    this.cancellationPolicy,
  }) : super(bookingType: BookingType.hotel);

  factory HotelBooking.fromJson(Map<String, dynamic> json) {
    return HotelBooking(
      bookingReference: json['booking_reference'] as String?,
      bookingDate: json['booking_date'] as String?,
      status: json['status'] as String?,
      contactInformation: ContactInformation.fromJson(
          json['contact_information'] as Map<String, dynamic>?),
      date: json['date'] as String?,
      pdfParseStatus: json['pdfParseStatus'] as String?,
      pdfParseError: json['pdfParseError'] as String?,
      origin: json['origin'] as String?,
      destination: json['destination'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      amountINR: (json['amountINR'] as num?)?.toDouble(),
      hotelName: json['hotel_name'] as String?,
      hotelBrand: json['hotel_brand'] as String?,
      address: Address.fromJson(json['address'] as Map<String, dynamic>?),
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
      nights: json['nights'] as int?,
      roomDetails: json['room_details'] as Map<String, dynamic>?,
      guests: (json['guests'] as List<dynamic>?)
              ?.map((e) => Passenger.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalAmount: Amount.fromJson(json['total_amount'] as Map<String, dynamic>?),
      amenities: (json['amenities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      cancellationPolicy: json['cancellation_policy'] as String?,
    );
  }
}

class TrainBooking extends Booking {
  final String? pnr;
  final String? trainNumber;
  final String? trainName;
  final Map<String, dynamic>? departure;
  final Map<String, dynamic>? arrival;
  final String? duration;
  final String? trainClass;
  final String? coach;
  final String? seatBerth;
  final List<Passenger> passengers;
  final Amount? totalAmount;

  TrainBooking({
    super.bookingReference,
    super.bookingDate,
    super.status,
    super.contactInformation,
    super.date,
    super.pdfParseStatus,
    super.pdfParseError,
    super.origin,
    super.destination,
    super.amount,
    super.currency,
    super.amountINR,
    this.pnr,
    this.trainNumber,
    this.trainName,
    this.departure,
    this.arrival,
    this.duration,
    this.trainClass,
    this.coach,
    this.seatBerth,
    this.passengers = const [],
    this.totalAmount,
  }) : super(bookingType: BookingType.train);

  factory TrainBooking.fromJson(Map<String, dynamic> json) {
    return TrainBooking(
      bookingReference: json['booking_reference'] as String?,
      bookingDate: json['booking_date'] as String?,
      status: json['status'] as String?,
      date: json['date'] as String?,
      pdfParseStatus: json['pdfParseStatus'] as String?,
      origin: json['origin'] as String?,
      destination: json['destination'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      amountINR: (json['amountINR'] as num?)?.toDouble(),
      pnr: json['pnr'] as String?,
      trainNumber: json['train_number'] as String?,
      trainName: json['train_name'] as String?,
      departure: json['departure'] as Map<String, dynamic>?,
      arrival: json['arrival'] as Map<String, dynamic>?,
      duration: json['duration'] as String?,
      trainClass: json['class'] as String?,
      coach: json['coach'] as String?,
      seatBerth: json['seat_berth'] as String?,
      passengers: (json['passengers'] as List<dynamic>?)
              ?.map((e) => Passenger.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalAmount: Amount.fromJson(json['total_amount'] as Map<String, dynamic>?),
    );
  }
}

class BusBooking extends Booking {
  final String? busOperator;
  final String? busType;
  final Map<String, dynamic>? departure;
  final Map<String, dynamic>? arrival;
  final String? duration;
  final List<String> seatNumbers;
  final List<Passenger> passengers;
  final Amount? totalAmount;
  final String? boardingPoint;
  final String? droppingPoint;

  BusBooking({
    super.bookingReference,
    super.bookingDate,
    super.status,
    super.date,
    super.pdfParseStatus,
    super.origin,
    super.destination,
    super.amount,
    super.currency,
    super.amountINR,
    this.busOperator,
    this.busType,
    this.departure,
    this.arrival,
    this.duration,
    this.seatNumbers = const [],
    this.passengers = const [],
    this.totalAmount,
    this.boardingPoint,
    this.droppingPoint,
  }) : super(bookingType: BookingType.bus);

  factory BusBooking.fromJson(Map<String, dynamic> json) {
    return BusBooking(
      bookingReference: json['booking_reference'] as String?,
      bookingDate: json['booking_date'] as String?,
      status: json['status'] as String?,
      date: json['date'] as String?,
      pdfParseStatus: json['pdfParseStatus'] as String?,
      origin: json['origin'] as String?,
      destination: json['destination'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      amountINR: (json['amountINR'] as num?)?.toDouble(),
      busOperator: json['bus_operator'] as String?,
      busType: json['bus_type'] as String?,
      departure: json['departure'] as Map<String, dynamic>?,
      arrival: json['arrival'] as Map<String, dynamic>?,
      duration: json['duration'] as String?,
      seatNumbers: (json['seat_numbers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      passengers: (json['passengers'] as List<dynamic>?)
              ?.map((e) => Passenger.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalAmount: Amount.fromJson(json['total_amount'] as Map<String, dynamic>?),
      boardingPoint: json['boarding_point'] as String?,
      droppingPoint: json['dropping_point'] as String?,
    );
  }
}

class EventBooking extends Booking {
  final String? eventName;
  final String? eventType;
  final Map<String, dynamic>? venue;
  final String? eventDate;
  final int? numberOfTickets;
  final Amount? totalAmount;

  EventBooking({
    super.bookingReference,
    super.bookingDate,
    super.status,
    super.date,
    super.pdfParseStatus,
    super.origin,
    super.destination,
    super.amount,
    super.currency,
    super.amountINR,
    this.eventName,
    this.eventType,
    this.venue,
    this.eventDate,
    this.numberOfTickets,
    this.totalAmount,
  }) : super(bookingType: BookingType.event);

  factory EventBooking.fromJson(Map<String, dynamic> json) {
    return EventBooking(
      bookingReference: json['booking_reference'] as String?,
      bookingDate: json['booking_date'] as String?,
      status: json['status'] as String?,
      date: json['date'] as String?,
      pdfParseStatus: json['pdfParseStatus'] as String?,
      destination: json['destination'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      amountINR: (json['amountINR'] as num?)?.toDouble(),
      eventName: json['event_name'] as String?,
      eventType: json['event_type'] as String?,
      venue: json['venue'] as Map<String, dynamic>?,
      eventDate: json['event_date'] as String?,
      numberOfTickets: json['number_of_tickets'] as int?,
      totalAmount: Amount.fromJson(json['total_amount'] as Map<String, dynamic>?),
    );
  }
}

class AttractionBooking extends Booking {
  final String? attractionName;
  final String? attractionType;
  final Map<String, dynamic>? location;
  final String? visitDate;
  final String? visitTime;
  final String? duration;
  final Amount? totalAmount;

  AttractionBooking({
    super.bookingReference,
    super.bookingDate,
    super.status,
    super.date,
    super.pdfParseStatus,
    super.origin,
    super.destination,
    super.amount,
    super.currency,
    super.amountINR,
    this.attractionName,
    this.attractionType,
    this.location,
    this.visitDate,
    this.visitTime,
    this.duration,
    this.totalAmount,
  }) : super(bookingType: BookingType.attraction);

  factory AttractionBooking.fromJson(Map<String, dynamic> json) {
    return AttractionBooking(
      bookingReference: json['booking_reference'] as String?,
      bookingDate: json['booking_date'] as String?,
      status: json['status'] as String?,
      date: json['date'] as String?,
      pdfParseStatus: json['pdfParseStatus'] as String?,
      destination: json['destination'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      amountINR: (json['amountINR'] as num?)?.toDouble(),
      attractionName: json['attraction_name'] as String?,
      attractionType: json['attraction_type'] as String?,
      location: json['location'] as Map<String, dynamic>?,
      visitDate: json['visit_date'] as String?,
      visitTime: json['visit_time'] as String?,
      duration: json['duration'] as String?,
      totalAmount: Amount.fromJson(json['total_amount'] as Map<String, dynamic>?),
    );
  }
}

class VisaBooking extends Booking {
  final String? applicationReference;
  final String? applicationDate;
  final String? visaType;
  final String? country;
  final Map<String, dynamic>? applicant;
  final Map<String, dynamic>? visaDetails;
  final Map<String, dynamic>? appointment;
  final Amount? fees;

  VisaBooking({
    super.bookingReference,
    super.bookingDate,
    super.status,
    super.date,
    super.pdfParseStatus,
    super.origin,
    super.destination,
    super.amount,
    super.currency,
    super.amountINR,
    this.applicationReference,
    this.applicationDate,
    this.visaType,
    this.country,
    this.applicant,
    this.visaDetails,
    this.appointment,
    this.fees,
  }) : super(bookingType: BookingType.visa);

  factory VisaBooking.fromJson(Map<String, dynamic> json) {
    return VisaBooking(
      bookingReference: json['booking_reference'] as String?,
      status: json['status'] as String?,
      date: json['date'] as String?,
      pdfParseStatus: json['pdfParseStatus'] as String?,
      destination: json['destination'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      amountINR: (json['amountINR'] as num?)?.toDouble(),
      applicationReference: json['application_reference'] as String?,
      applicationDate: json['application_date'] as String?,
      visaType: json['visa_type'] as String?,
      country: json['country'] as String?,
      applicant: json['applicant'] as Map<String, dynamic>?,
      visaDetails: json['visa_details'] as Map<String, dynamic>?,
      appointment: json['appointment'] as Map<String, dynamic>?,
      fees: Amount.fromJson(json['fees'] as Map<String, dynamic>?),
    );
  }
}

class VacationRentalBooking extends Booking {
  final String? propertyName;
  final String? propertyType;
  final String? hostName;
  final Address? address;
  final String? checkIn;
  final String? checkOut;
  final int? nights;
  final int? guests;
  final Amount? totalAmount;
  final List<String> amenities;
  final String? houseRules;
  final String? cancellationPolicy;

  VacationRentalBooking({
    super.bookingReference,
    super.bookingDate,
    super.status,
    super.date,
    super.pdfParseStatus,
    super.origin,
    super.destination,
    super.amount,
    super.currency,
    super.amountINR,
    this.propertyName,
    this.propertyType,
    this.hostName,
    this.address,
    this.checkIn,
    this.checkOut,
    this.nights,
    this.guests,
    this.totalAmount,
    this.amenities = const [],
    this.houseRules,
    this.cancellationPolicy,
  }) : super(bookingType: BookingType.vacationRental);

  factory VacationRentalBooking.fromJson(Map<String, dynamic> json) {
    return VacationRentalBooking(
      bookingReference: json['booking_reference'] as String?,
      bookingDate: json['booking_date'] as String?,
      status: json['status'] as String?,
      date: json['date'] as String?,
      pdfParseStatus: json['pdfParseStatus'] as String?,
      destination: json['destination'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      amountINR: (json['amountINR'] as num?)?.toDouble(),
      propertyName: json['property_name'] as String?,
      propertyType: json['property_type'] as String?,
      hostName: json['host_name'] as String?,
      address: Address.fromJson(json['address'] as Map<String, dynamic>?),
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
      nights: json['nights'] as int?,
      guests: json['guests'] as int?,
      totalAmount: Amount.fromJson(json['total_amount'] as Map<String, dynamic>?),
      amenities: (json['amenities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      houseRules: json['house_rules'] as String?,
      cancellationPolicy: json['cancellation_policy'] as String?,
    );
  }
}
