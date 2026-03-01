import ActivityKit
import Foundation

struct TrainTrackingAttributes: ActivityAttributes {
    // Static data — set once when the activity starts, never changes
    var trainNumber: String
    var trainName: String
    var originStation: String
    var originCode: String
    var destinationStation: String
    var destinationCode: String

    // Dynamic data — changes over the lifetime of the activity
    public struct ContentState: Codable, Hashable {
        var currentStation: String?
        var currentStationCode: String?
        var nextStation: String?
        var nextStationCode: String?
        var nextStationArrival: String?   // e.g. "14:30"
        var destinationArrival: String?   // e.g. "05:45"
        var delayMinutes: Int
        var platform: Int?
        var status: String                // "not_started", "running", "arrived", "completed"
        var lastUpdated: String?
        var progress: Int                 // 0-100 based on stations passed
    }
}
