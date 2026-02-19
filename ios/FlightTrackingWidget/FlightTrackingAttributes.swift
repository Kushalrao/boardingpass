import ActivityKit
import Foundation

struct FlightTrackingAttributes: ActivityAttributes {
    // Static data — set once when the activity starts, never changes
    var flightNumber: String
    var originCity: String
    var destinationCity: String
    var originAirport: String
    var destinationAirport: String
    var scheduledDeparture: Date
    var scheduledArrival: Date

    // Dynamic data — changes over the lifetime of the activity
    public struct ContentState: Codable, Hashable {
        var status: String              // "Scheduled", "Boarding", "In Flight", "Landed", "Cancelled", "Diverted"
        var departureGate: String?
        var arrivalGate: String?
        var departureTerminal: String?
        var arrivalTerminal: String?
        var estimatedDeparture: Date
        var estimatedArrival: Date
        var delayMinutes: Int
        var progress: Int               // 0-100
        var baggageBelt: String?
        var diversionAirport: String?
    }
}
