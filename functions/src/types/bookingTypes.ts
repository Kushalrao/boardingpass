export type BookingType = 'flight' | 'hotel' | 'train' | 'bus' | 'event' | 'attraction' | 'visa' | 'vacation_rental';

export interface Amount {
  amount: number | null;
  currency: string | null;
}

export interface Passenger {
  name: string | null;
  type: string | null;
  ticket_number?: string | null;
  seat_number?: string | null;
  meal_preference?: string | null;
  age?: number | null;
  gender?: string | null;
}

export interface FlightLocation {
  city: string | null;
  airport: string | null;
  airport_code: string | null;
  terminal: string | null;
  datetime: string | null;
  latitude?: number | null;
  longitude?: number | null;
}

export interface FlightSegment {
  flight_number: string | null;
  airline: string | null;
  operated_by?: string | null;
  departure: FlightLocation;
  arrival: FlightLocation;
  class: string | null;
  fare_type: string | null;
  duration: string | null;
  baggage_allowance?: {
    checkin: string | null;
    cabin: string | null;
  };
  seat_assignments?: Array<{
    passenger_name: string | null;
    seat_number: string | null;
  }>;
}

export interface FareBreakdown {
  base_fare?: Amount;
  room_rate?: Amount;
  nightly_rate?: Amount;
  cleaning_fee?: Amount;
  service_fee?: Amount;
  taxes?: Amount;
  fees?: Amount;
  discounts?: Amount;
  reservation_charges?: Amount;
  booking_fees?: Amount;
  ticket_price?: Amount;
  total: Amount;
}

export interface ContactInformation {
  email: string | null;
  phone: string | null;
}

export interface Address {
  street?: string | null;
  city: string | null;
  state?: string | null;
  country?: string | null;
  postal_code?: string | null;
}

export interface BaseBooking {
  booking_type: BookingType;
  booking_reference?: string | null;
  booking_date?: string | null;
  status?: string | null;
  contact_information?: ContactInformation;
  date?: string;
  pdfParseStatus?: string;
  pdfParseError?: string;
  origin?: string;
  destination?: string;
  amount?: number;
  currency?: string;
  amountINR?: number;
}

export interface FlightBooking extends BaseBooking {
  booking_type: 'flight';
  airline?: string;
  trip_type?: string | null;
  total_amount_paid?: Amount;
  passengers?: Passenger[];
  flights?: FlightSegment[];
  fare_breakdown?: FareBreakdown;
  additional_info?: string | null;
}

export interface HotelBooking extends BaseBooking {
  booking_type: 'hotel';
  hotel_name: string;
  hotel_brand?: string | null;
  address: Address;
  check_in: string;
  check_out: string;
  nights: number;
  room_details?: {
    room_type?: string | null;
    bed_type?: string | null;
    number_of_rooms?: number | null;
    number_of_guests?: number | null;
  };
  guests?: Passenger[];
  total_amount: Amount;
  fare_breakdown?: FareBreakdown;
  amenities?: string[];
  cancellation_policy?: string | null;
}

export interface TrainBooking extends BaseBooking {
  booking_type: 'train';
  pnr: string;
  train_number: string;
  train_name: string;
  departure: {
    station: string | null;
    station_code: string | null;
    city: string | null;
    datetime: string | null;
    platform?: string | null;
  };
  arrival: {
    station: string | null;
    station_code: string | null;
    city: string | null;
    datetime: string | null;
    platform?: string | null;
  };
  duration: string | null;
  class: string | null;
  coach?: string | null;
  seat_berth?: string | null;
  passengers?: Passenger[];
  total_amount: Amount;
  fare_breakdown?: FareBreakdown;
}

export interface BusBooking extends BaseBooking {
  booking_type: 'bus';
  bus_operator: string;
  bus_type?: string | null;
  departure: {
    location: string | null;
    city: string | null;
    datetime: string | null;
  };
  arrival: {
    location: string | null;
    city: string | null;
    datetime: string | null;
  };
  duration: string | null;
  seat_numbers?: string[];
  passengers?: Passenger[];
  total_amount: Amount;
  amenities?: string[];
  boarding_point?: string | null;
  dropping_point?: string | null;
}

export interface EventBooking extends BaseBooking {
  booking_type: 'event';
  event_name: string;
  event_type?: string | null;
  venue: {
    name: string | null;
    address: string | null;
    city: string | null;
    country: string | null;
  };
  event_date: string;
  doors_open?: string | null;
  seats?: Array<{
    section?: string | null;
    row?: string | null;
    seat_number?: string | null;
    ticket_holder?: string | null;
  }>;
  number_of_tickets: number;
  total_amount: Amount;
  fare_breakdown?: FareBreakdown;
  barcode_qr?: string | null;
}

export interface AttractionBooking extends BaseBooking {
  booking_type: 'attraction';
  attraction_name: string;
  attraction_type?: string | null;
  location: {
    name?: string | null;
    address?: string | null;
    city: string | null;
    country?: string | null;
  };
  visit_date: string;
  visit_time?: string | null;
  duration?: string | null;
  tickets?: Array<{
    type: string | null;
    quantity: number | null;
    holder_name?: string | null;
  }>;
  total_amount: Amount;
  includes?: string[];
  meeting_point?: string | null;
}

export interface VisaBooking extends BaseBooking {
  booking_type: 'visa';
  application_reference: string;
  application_date: string;
  visa_type: string;
  country: string;
  applicant: {
    name: string | null;
    passport_number: string | null;
    nationality: string | null;
    date_of_birth: string | null;
  };
  visa_details?: {
    visa_number?: string | null;
    validity_from?: string | null;
    validity_to?: string | null;
    duration?: string | null;
    entries?: string | null;
  };
  appointment?: {
    date: string | null;
    time: string | null;
    location: string | null;
    address: string | null;
  };
  fees: Amount;
}

export interface VacationRentalBooking extends BaseBooking {
  booking_type: 'vacation_rental';
  property_name: string;
  property_type?: string | null;
  host_name?: string | null;
  address: Address;
  check_in: string;
  check_out: string;
  nights: number;
  guests: number;
  total_amount: Amount;
  fare_breakdown?: FareBreakdown;
  amenities?: string[];
  house_rules?: string | null;
  cancellation_policy?: string | null;
}

export type Booking =
  | FlightBooking
  | HotelBooking
  | TrainBooking
  | BusBooking
  | EventBooking
  | AttractionBooking
  | VisaBooking
  | VacationRentalBooking;

export interface TravelAnalysisResponse {
  travels: Booking[];
  moreBatches: boolean;
  nextBatch: number | null;
  totalEmails?: number;
}

export interface AnalyzeTravelRequest {
  accessToken: string;
  options?: {
    batchSize?: number;
    batch?: number;
    year?: number;
  };
}
