"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SYSTEM_PROMPTS = exports.SCHEMAS = void 0;
exports.SCHEMAS = {
    flight: `{
  "booking_type": "flight",
  "booking_reference": "string",
  "booking_date": "YYYY-MM-DD",
  "trip_type": "one-way | round-trip | multi-city",
  "total_amount_paid": {
    "amount": "number",
    "currency": "string"
  },
  "passengers": [
    {
      "name": "string",
      "type": "ADT | CHD | INF",
      "ticket_number": "string",
      "seat_number": "string",
      "meal_preference": "string"
    }
  ],
  "flights": [
    {
      "flight_number": "string",
      "airline": "string",
      "operated_by": "string (optional)",
      "departure": {
        "city": "string",
        "airport": "string",
        "airport_code": "string",
        "terminal": "string",
        "datetime": "YYYY-MM-DDTHH:mm",
        "latitude": "number (if known)",
        "longitude": "number (if known)"
      },
      "arrival": {
        "city": "string",
        "airport": "string",
        "airport_code": "string",
        "terminal": "string",
        "datetime": "YYYY-MM-DDTHH:mm",
        "latitude": "number (if known)",
        "longitude": "number (if known)"
      },
      "class": "string",
      "fare_type": "string",
      "duration": "string",
      "baggage_allowance": {
        "checkin": "string",
        "cabin": "string"
      }
    }
  ],
  "fare_breakdown": {
    "base_fare": { "amount": "number", "currency": "string" },
    "taxes": { "amount": "number", "currency": "string" },
    "fees": { "amount": "number", "currency": "string" },
    "discounts": { "amount": "number", "currency": "string" },
    "total": { "amount": "number", "currency": "string" }
  },
  "contact_information": { "email": "string", "phone": "string" },
  "status": "Confirmed | Cancelled | Pending",
  "additional_info": "string"
}`,
    hotel: `{
  "booking_type": "hotel",
  "booking_reference": "string",
  "booking_date": "YYYY-MM-DD",
  "hotel_name": "string",
  "hotel_brand": "string",
  "address": {
    "street": "string",
    "city": "string",
    "state": "string",
    "country": "string",
    "postal_code": "string"
  },
  "check_in": "YYYY-MM-DDTHH:mm",
  "check_out": "YYYY-MM-DDTHH:mm",
  "nights": "number",
  "room_details": {
    "room_type": "string",
    "bed_type": "string",
    "number_of_rooms": "number",
    "number_of_guests": "number"
  },
  "guests": [{"name": "string", "type": "ADT | CHD"}],
  "total_amount": { "amount": "number", "currency": "string" },
  "fare_breakdown": {
    "room_rate": {"amount": "number", "currency": "string"},
    "taxes": {"amount": "number", "currency": "string"},
    "fees": {"amount": "number", "currency": "string"},
    "total": {"amount": "number", "currency": "string"}
  },
  "amenities": ["string"],
  "cancellation_policy": "string",
  "status": "Confirmed | Cancelled | Pending",
  "contact_info": {"email": "string", "phone": "string"}
}`,
    train: `{
  "booking_type": "train",
  "pnr": "string",
  "booking_reference": "string",
  "booking_date": "YYYY-MM-DD",
  "train_number": "string",
  "train_name": "string",
  "departure": {
    "station": "string",
    "station_code": "string",
    "city": "string",
    "datetime": "YYYY-MM-DDTHH:mm",
    "platform": "string"
  },
  "arrival": {
    "station": "string",
    "station_code": "string",
    "city": "string",
    "datetime": "YYYY-MM-DDTHH:mm",
    "platform": "string"
  },
  "duration": "string",
  "class": "string",
  "coach": "string",
  "seat_berth": "string",
  "passengers": [
    {
      "name": "string",
      "age": "number",
      "gender": "string",
      "seat_berth": "string",
      "status": "Confirmed | RAC | Waiting"
    }
  ],
  "total_amount": { "amount": "number", "currency": "string" },
  "status": "Confirmed | Cancelled | RAC | Waiting",
  "contact_info": {"email": "string", "phone": "string"}
}`,
    bus: `{
  "booking_type": "bus",
  "booking_reference": "string",
  "booking_date": "YYYY-MM-DD",
  "bus_operator": "string",
  "bus_type": "string",
  "departure": {
    "location": "string",
    "city": "string",
    "datetime": "YYYY-MM-DDTHH:mm"
  },
  "arrival": {
    "location": "string",
    "city": "string",
    "datetime": "YYYY-MM-DDTHH:mm"
  },
  "duration": "string",
  "seat_numbers": ["string"],
  "passengers": [{"name": "string", "age": "number", "gender": "string"}],
  "total_amount": { "amount": "number", "currency": "string" },
  "amenities": ["string"],
  "boarding_point": "string",
  "dropping_point": "string",
  "status": "Confirmed | Cancelled",
  "contact_info": {"email": "string", "phone": "string"}
}`,
    event: `{
  "booking_type": "event",
  "booking_reference": "string",
  "booking_date": "YYYY-MM-DD",
  "event_name": "string",
  "event_type": "string",
  "venue": {
    "name": "string",
    "address": "string",
    "city": "string",
    "country": "string"
  },
  "event_date": "YYYY-MM-DDTHH:mm",
  "doors_open": "YYYY-MM-DDTHH:mm",
  "seats": [
    {
      "section": "string",
      "row": "string",
      "seat_number": "string",
      "ticket_holder": "string"
    }
  ],
  "number_of_tickets": "number",
  "total_amount": { "amount": "number", "currency": "string" },
  "barcode_qr": "string",
  "status": "Confirmed | Cancelled",
  "contact_info": {"email": "string", "phone": "string"}
}`,
    attraction: `{
  "booking_type": "attraction",
  "booking_reference": "string",
  "booking_date": "YYYY-MM-DD",
  "attraction_name": "string",
  "attraction_type": "string",
  "location": {
    "name": "string",
    "address": "string",
    "city": "string",
    "country": "string"
  },
  "visit_date": "YYYY-MM-DD",
  "visit_time": "HH:mm",
  "duration": "string",
  "tickets": [
    {
      "type": "string",
      "quantity": "number",
      "holder_name": "string"
    }
  ],
  "total_amount": { "amount": "number", "currency": "string" },
  "includes": ["string"],
  "meeting_point": "string",
  "status": "Confirmed | Cancelled",
  "contact_info": {"email": "string", "phone": "string"}
}`,
    visa: `{
  "booking_type": "visa",
  "application_reference": "string",
  "application_date": "YYYY-MM-DD",
  "visa_type": "string",
  "country": "string",
  "applicant": {
    "name": "string",
    "passport_number": "string",
    "nationality": "string",
    "date_of_birth": "YYYY-MM-DD"
  },
  "visa_details": {
    "visa_number": "string",
    "validity_from": "YYYY-MM-DD",
    "validity_to": "YYYY-MM-DD",
    "duration": "string",
    "entries": "string"
  },
  "appointment": {
    "date": "YYYY-MM-DD",
    "time": "HH:mm",
    "location": "string",
    "address": "string"
  },
  "fees": { "amount": "number", "currency": "string" },
  "status": "Approved | Pending | Rejected | Appointment Scheduled",
  "contact_info": {"email": "string", "phone": "string"}
}`,
    vacation_rental: `{
  "booking_type": "vacation_rental",
  "booking_reference": "string",
  "booking_date": "YYYY-MM-DD",
  "property_name": "string",
  "property_type": "string",
  "host_name": "string",
  "address": {
    "street": "string",
    "city": "string",
    "state": "string",
    "country": "string",
    "postal_code": "string"
  },
  "check_in": "YYYY-MM-DDTHH:mm",
  "check_out": "YYYY-MM-DDTHH:mm",
  "nights": "number",
  "guests": "number",
  "total_amount": { "amount": "number", "currency": "string" },
  "fare_breakdown": {
    "nightly_rate": {"amount": "number", "currency": "string"},
    "cleaning_fee": {"amount": "number", "currency": "string"},
    "service_fee": {"amount": "number", "currency": "string"},
    "taxes": {"amount": "number", "currency": "string"},
    "total": {"amount": "number", "currency": "string"}
  },
  "amenities": ["string"],
  "house_rules": "string",
  "cancellation_policy": "string",
  "status": "Confirmed | Cancelled",
  "contact_info": {"email": "string", "phone": "string"}
}`
};
exports.SYSTEM_PROMPTS = {
    flight: `You are a travel assistant. Extract all possible information from the following flight ticket/e-ticket text and return it as a JSON object using this schema:\n\n${exports.SCHEMAS.flight}\n\nIf any field is missing or not available, use null. If there are multiple flights (layovers, multi-city), include each as a separate object in the flights array. Use ISO 8601 format for all dates and times.\n\nIMPORTANT: For the departure and arrival locations, if you know the airport code (e.g., SFO, DEL, NRT), please also provide the latitude and longitude coordinates for that airport.`,
    hotel: `You are a travel assistant. Extract all possible information from the following hotel booking confirmation and return it as a JSON object using this schema:\n\n${exports.SCHEMAS.hotel}\n\nIf any field is missing or not available, use null. Extract all guest information, room details, and pricing breakdown. Use ISO 8601 format for check-in/check-out times.`,
    vacation_rental: `You are a travel assistant. Extract all possible information from the following Airbnb/vacation rental booking and return it as a JSON object using this schema:\n\n${exports.SCHEMAS.vacation_rental}\n\nIf any field is missing or not available, use null. Extract property details, host information, and all pricing components. Use ISO 8601 format for dates and times.`,
    train: `You are a travel assistant. Extract all possible information from the following train ticket/reservation and return it as a JSON object using this schema:\n\n${exports.SCHEMAS.train}\n\nIf any field is missing or not available, use null. Extract PNR, train details, passenger information with berth/seat assignments. Use ISO 8601 format for departure/arrival times.`,
    bus: `You are a travel assistant. Extract all possible information from the following bus ticket and return it as a JSON object using this schema:\n\n${exports.SCHEMAS.bus}\n\nIf any field is missing or not available, use null. Extract bus operator, seat numbers, boarding/dropping points, and passenger details.`,
    event: `You are a travel assistant. Extract all possible information from the following event ticket and return it as a JSON object using this schema:\n\n${exports.SCHEMAS.event}\n\nIf any field is missing or not available, use null. Extract event details, venue information, seat assignments, and ticket holder names.`,
    attraction: `You are a travel assistant. Extract all possible information from the following attraction/tour ticket and return it as a JSON object using this schema:\n\n${exports.SCHEMAS.attraction}\n\nIf any field is missing or not available, use null. Extract attraction name, visit date/time, ticket types and quantities, and what's included.`,
    visa: `You are a travel assistant. Extract all possible information from the following visa confirmation/appointment and return it as a JSON object using this schema:\n\n${exports.SCHEMAS.visa}\n\nIf any field is missing or not available, use null. Extract applicant details, visa information, appointment details if any, and application status.`
};
//# sourceMappingURL=schemas.js.map