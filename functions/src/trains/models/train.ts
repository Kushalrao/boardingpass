/**
 * Train data models for Indian Railways
 */

export interface Station {
  code: string;
  name: string;
  time?: string;
}

export interface Passenger {
  number: number;
  bookingStatus: string;
  currentStatus: string;
  coach?: string;
  berth?: string;
}

export interface PnrStatus {
  success: boolean;
  pnr: string;
  trainNumber?: string;
  trainName?: string;
  journeyDate?: string;
  fromStation?: Station;
  toStation?: Station;
  travelClass?: string;
  quota?: string;
  passengers: Passenger[];
  chartStatus?: string;
  overallStatus?: string;
  confirmationChance?: string;
  error?: string;
}

export interface ScheduleStation {
  code: string;
  name: string;
  arrival?: string;
  departure?: string;
  halt?: string;
  distance?: number;
  dayNumber?: number;
}

export interface TrainSchedule {
  success: boolean;
  trainNumber: string;
  trainName?: string;
  runningDays: string[];
  stations: ScheduleStation[];
  error?: string;
}

export interface LiveStationStatus {
  code: string;
  name: string;
  scheduledArrival?: string;
  actualArrival?: string;
  delay?: number;
  status: 'departed' | 'arrived' | 'upcoming';
}

export interface LiveStatus {
  success: boolean;
  trainNumber: string;
  trainName?: string;
  currentStation?: string;
  lastUpdated?: string;
  delay?: number;
  stations: LiveStationStatus[];
  error?: string;
}

export interface SearchTrain {
  trainNumber: string;
  trainName: string;
  departure: string;
  arrival: string;
  duration?: string;
  runningDays: string[];
}

export interface SearchTrainsResult {
  success: boolean;
  trains: SearchTrain[];
  error?: string;
}

/**
 * Train booking stored in Firestore
 */
export interface TrainBooking {
  // Identifiers
  id?: string;
  pnr?: string;
  trainNumber: string;
  trainName?: string;

  // Journey details
  journeyDate: Date | string;
  fromStation: Station;
  toStation: Station;

  // Booking details
  travelClass?: string;
  quota?: string;
  passengers: Passenger[];

  // Status
  chartStatus?: string;
  overallStatus?: string;
  confirmationChance?: string;

  // Live tracking
  liveStatus?: {
    currentStation?: string;
    delay?: number;
    lastUpdated?: Date | string;
  };

  // Metadata
  source: 'manual' | 'webhook' | 'query';
  savedAt: Date | string;
  lastChecked?: Date | string;
}

/**
 * Request types for callable functions
 */
export interface AddTrainRequest {
  pnr?: string;
  trainNumber?: string;
  journeyDate: string;
  fromStation?: string;
  toStation?: string;
}

export interface RefreshTrainRequest {
  trainId: string;
}

export interface GetUserTrainsRequest {
  upcoming?: boolean;
  limit?: number;
}
