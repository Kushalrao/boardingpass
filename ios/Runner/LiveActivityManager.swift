import ActivityKit
import Flutter
import Foundation

@available(iOS 16.2, *)
class LiveActivityManager {
    static let shared = LiveActivityManager()

    // Maps Firestore flight ID → ActivityKit activity ID
    private var activeActivities: [String: String] = [:]

    // Maps train ID → ActivityKit activity ID
    private var activeTrainActivities: [String: String] = [:]

    // Callback to send push tokens back to Dart
    var onPushTokenUpdate: ((String, String) -> Void)?  // (flightId, tokenHex)

    // MARK: - Start Live Activity

    func startActivity(params: [String: Any], completion: @escaping (Result<[String: String], Error>) -> Void) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            completion(.failure(LiveActivityError.notSupported))
            return
        }

        guard let flightId = params["flightId"] as? String,
              let flightNumber = params["flightNumber"] as? String,
              let originCity = params["originCity"] as? String,
              let destinationCity = params["destinationCity"] as? String,
              let originAirport = params["originAirport"] as? String,
              let destinationAirport = params["destinationAirport"] as? String,
              let scheduledDepartureMs = params["scheduledDeparture"] as? Double,
              let scheduledArrivalMs = params["scheduledArrival"] as? Double
        else {
            completion(.failure(LiveActivityError.invalidParams))
            return
        }

        let scheduledDeparture = Date(timeIntervalSince1970: scheduledDepartureMs / 1000.0)
        let scheduledArrival = Date(timeIntervalSince1970: scheduledArrivalMs / 1000.0)

        let attributes = FlightTrackingAttributes(
            flightNumber: flightNumber,
            originCity: originCity,
            destinationCity: destinationCity,
            originAirport: originAirport,
            destinationAirport: destinationAirport,
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival
        )

        let initialState = buildContentState(from: params, scheduledDeparture: scheduledDeparture, scheduledArrival: scheduledArrival)

        do {
            let activity = try Activity<FlightTrackingAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(3600)),
                pushType: .token
            )

            activeActivities[flightId] = activity.id

            print("[LiveActivity] Started activity \(activity.id) for \(flightNumber)")

            // Observe push token updates
            Task {
                for await pushToken in activity.pushTokenUpdates {
                    let tokenHex = pushToken.reduce("") { $0 + String(format: "%02x", $1) }
                    print("[LiveActivity] Push token for \(flightNumber): \(tokenHex)")
                    self.onPushTokenUpdate?(flightId, tokenHex)
                }
            }

            var result: [String: String] = ["activityId": activity.id]

            // Try to get initial push token
            if let token = activity.pushToken {
                let tokenHex = token.reduce("") { $0 + String(format: "%02x", $1) }
                result["pushToken"] = tokenHex
            }

            completion(.success(result))
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
            completion(.failure(error))
        }
    }

    // MARK: - Update Live Activity

    func updateActivity(params: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let flightId = params["flightId"] as? String,
              let activityId = activeActivities[flightId]
        else {
            completion(.failure(LiveActivityError.activityNotFound))
            return
        }

        let scheduledDepartureMs = params["scheduledDeparture"] as? Double ?? 0
        let scheduledArrivalMs = params["scheduledArrival"] as? Double ?? 0
        let scheduledDeparture = Date(timeIntervalSince1970: scheduledDepartureMs / 1000.0)
        let scheduledArrival = Date(timeIntervalSince1970: scheduledArrivalMs / 1000.0)

        let updatedState = buildContentState(from: params, scheduledDeparture: scheduledDeparture, scheduledArrival: scheduledArrival)

        Task {
            for activity in Activity<FlightTrackingAttributes>.activities where activity.id == activityId {
                await activity.update(
                    ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(3600))
                )
                print("[LiveActivity] Updated activity \(activityId)")
                completion(.success(()))
                return
            }
            completion(.failure(LiveActivityError.activityNotFound))
        }
    }

    // MARK: - End Live Activity

    func endActivity(params: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let flightId = params["flightId"] as? String,
              let activityId = activeActivities[flightId]
        else {
            completion(.failure(LiveActivityError.activityNotFound))
            return
        }

        let scheduledDepartureMs = params["scheduledDeparture"] as? Double ?? 0
        let scheduledArrivalMs = params["scheduledArrival"] as? Double ?? 0
        let scheduledDeparture = Date(timeIntervalSince1970: scheduledDepartureMs / 1000.0)
        let scheduledArrival = Date(timeIntervalSince1970: scheduledArrivalMs / 1000.0)

        let finalState = buildContentState(from: params, scheduledDeparture: scheduledDeparture, scheduledArrival: scheduledArrival)

        Task {
            for activity in Activity<FlightTrackingAttributes>.activities where activity.id == activityId {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .default
                )
                print("[LiveActivity] Ended activity \(activityId)")
                activeActivities.removeValue(forKey: flightId)
                completion(.success(()))
                return
            }
            activeActivities.removeValue(forKey: flightId)
            completion(.failure(LiveActivityError.activityNotFound))
        }
    }

    // MARK: - End All Activities

    func endAllActivities() {
        Task {
            for activity in Activity<FlightTrackingAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            activeActivities.removeAll()
            print("[LiveActivity] Ended all activities")
        }
    }

    // MARK: - Check Support

    func areActivitiesEnabled() -> Bool {
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Build ContentState from params dict

    private func buildContentState(
        from params: [String: Any],
        scheduledDeparture: Date,
        scheduledArrival: Date
    ) -> FlightTrackingAttributes.ContentState {
        let status = params["status"] as? String ?? "Scheduled"
        let delayMinutes = params["delayMinutes"] as? Int ?? 0
        let progress = params["progress"] as? Int ?? 0

        let estDepartureMs = params["estimatedDeparture"] as? Double
        let estArrivalMs = params["estimatedArrival"] as? Double

        let estimatedDeparture = estDepartureMs != nil
            ? Date(timeIntervalSince1970: estDepartureMs! / 1000.0)
            : scheduledDeparture
        let estimatedArrival = estArrivalMs != nil
            ? Date(timeIntervalSince1970: estArrivalMs! / 1000.0)
            : scheduledArrival

        return FlightTrackingAttributes.ContentState(
            status: status,
            departureGate: params["departureGate"] as? String,
            arrivalGate: params["arrivalGate"] as? String,
            departureTerminal: params["departureTerminal"] as? String,
            arrivalTerminal: params["arrivalTerminal"] as? String,
            estimatedDeparture: estimatedDeparture,
            estimatedArrival: estimatedArrival,
            delayMinutes: delayMinutes,
            progress: progress,
            baggageBelt: params["baggageBelt"] as? String,
            diversionAirport: params["diversionAirport"] as? String
        )
    }
    // MARK: - Train Live Activity

    func startTrainActivity(params: [String: Any], completion: @escaping (Result<[String: String], Error>) -> Void) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            completion(.failure(LiveActivityError.notSupported))
            return
        }

        guard let trainId = params["trainId"] as? String,
              let trainNumber = params["trainNumber"] as? String,
              let trainName = params["trainName"] as? String,
              let originStation = params["originStation"] as? String,
              let originCode = params["originCode"] as? String,
              let destinationStation = params["destinationStation"] as? String,
              let destinationCode = params["destinationCode"] as? String
        else {
            completion(.failure(LiveActivityError.invalidParams))
            return
        }

        let attributes = TrainTrackingAttributes(
            trainNumber: trainNumber,
            trainName: trainName,
            originStation: originStation,
            originCode: originCode,
            destinationStation: destinationStation,
            destinationCode: destinationCode
        )

        let initialState = buildTrainContentState(from: params)

        do {
            let activity = try Activity<TrainTrackingAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(300))
            )

            activeTrainActivities[trainId] = activity.id
            print("[TrainLiveActivity] Started activity \(activity.id) for \(trainNumber)")

            completion(.success(["activityId": activity.id]))
        } catch {
            print("[TrainLiveActivity] Failed to start: \(error)")
            completion(.failure(error))
        }
    }

    func updateTrainActivity(params: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let trainId = params["trainId"] as? String,
              let activityId = activeTrainActivities[trainId]
        else {
            completion(.failure(LiveActivityError.activityNotFound))
            return
        }

        let updatedState = buildTrainContentState(from: params)

        Task {
            for activity in Activity<TrainTrackingAttributes>.activities where activity.id == activityId {
                await activity.update(
                    ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(300))
                )
                print("[TrainLiveActivity] Updated activity \(activityId)")
                completion(.success(()))
                return
            }
            completion(.failure(LiveActivityError.activityNotFound))
        }
    }

    func endTrainActivity(params: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let trainId = params["trainId"] as? String,
              let activityId = activeTrainActivities[trainId]
        else {
            completion(.failure(LiveActivityError.activityNotFound))
            return
        }

        let finalState = buildTrainContentState(from: params)

        Task {
            for activity in Activity<TrainTrackingAttributes>.activities where activity.id == activityId {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .default
                )
                print("[TrainLiveActivity] Ended activity \(activityId)")
                activeTrainActivities.removeValue(forKey: trainId)
                completion(.success(()))
                return
            }
            activeTrainActivities.removeValue(forKey: trainId)
            completion(.failure(LiveActivityError.activityNotFound))
        }
    }

    private func buildTrainContentState(from params: [String: Any]) -> TrainTrackingAttributes.ContentState {
        return TrainTrackingAttributes.ContentState(
            currentStation: params["currentStation"] as? String,
            currentStationCode: params["currentStationCode"] as? String,
            nextStation: params["nextStation"] as? String,
            nextStationCode: params["nextStationCode"] as? String,
            nextStationArrival: params["nextStationArrival"] as? String,
            destinationArrival: params["destinationArrival"] as? String,
            delayMinutes: params["delayMinutes"] as? Int ?? 0,
            platform: params["platform"] as? Int,
            status: params["status"] as? String ?? "not_started",
            lastUpdated: params["lastUpdated"] as? String,
            progress: params["progress"] as? Int ?? 0
        )
    }
}

// MARK: - Errors

enum LiveActivityError: LocalizedError {
    case notSupported
    case invalidParams
    case activityNotFound

    var errorDescription: String? {
        switch self {
        case .notSupported: return "Live Activities are not supported or disabled"
        case .invalidParams: return "Invalid parameters for Live Activity"
        case .activityNotFound: return "Live Activity not found"
        }
    }
}
