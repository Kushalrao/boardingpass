import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Design Tokens

@available(iOS 16.2, *)
private enum T {
    static let bluePill = Color(red: 1/255, green: 107/255, blue: 229/255)
    static let bluePillText = Color(red: 205/255, green: 249/255, blue: 218/255)
    static let yellowPill = Color(red: 255/255, green: 204/255, blue: 0)
    static let yellowPillText = Color(red: 109/255, green: 89/255, blue: 11/255)
    static let greenProgress = Color(red: 9/255, green: 200/255, blue: 66/255)
    static let orangeDelay = Color(red: 255/255, green: 70/255, blue: 0)
    static let routeBg = Color(red: 245/255, green: 245/255, blue: 240/255)
    static let subtitleColor = Color.black.opacity(0.62)
    static let delayGradientStart = Color(red: 154/255, green: 4/255, blue: 75/255)
    static let delayGradientEnd = Color(red: 81/255, green: 2/255, blue: 40/255)
    static let delayBorder = Color(red: 255/255, green: 70/255, blue: 0)
    static let delayTextLight = Color(red: 255/255, green: 234/255, blue: 226/255)
}

// MARK: - Train Activity Widget

@available(iOS 16.2, *)
struct TrainActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainTrackingAttributes.self) { context in
            // Lock Screen view
            TrainLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .padding(16)
            .background(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.trainNumber)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.delayMinutes > 0 {
                        Text("+\(context.state.delayMinutes)m")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(T.orangeDelay)
                    } else {
                        Text("On Time")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(T.greenProgress)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TrainDIExpandedBottom(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
            } compactLeading: {
                // Train icon + number
                HStack(spacing: 3) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 10))
                    Text(context.attributes.trainNumber)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
            } compactTrailing: {
                // Delay or next station
                if context.state.delayMinutes > 0 {
                    Text("+\(context.state.delayMinutes)m")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(T.orangeDelay)
                } else if let next = context.state.nextStationCode, !next.isEmpty {
                    Text(next)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(T.bluePillText)
                } else {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
            } minimal: {
                Image(systemName: "tram.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Dynamic Island Expanded Bottom

@available(iOS 16.2, *)
struct TrainDIExpandedBottom: View {
    let attributes: TrainTrackingAttributes
    let state: TrainTrackingAttributes.ContentState

    var body: some View {
        VStack(spacing: 6) {
            // Route: Origin → Destination with progress
            HStack {
                Text(attributes.originCode)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 3)
                        Capsule()
                            .fill(T.greenProgress)
                            .frame(width: geo.size.width * CGFloat(state.progress) / 100.0, height: 3)
                    }
                }
                .frame(height: 3)

                Text(attributes.destinationCode)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            // Current station info
            if let current = state.currentStation, !current.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(T.greenProgress)
                        .frame(width: 6, height: 6)
                    Text("At \(current)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    if let eta = state.destinationArrival, !eta.isEmpty {
                        Text("ETA \(eta)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            } else if let next = state.nextStation, !next.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Next: \(next)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    if let eta = state.destinationArrival, !eta.isEmpty {
                        Text("ETA \(eta)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }
}

// MARK: - Lock Screen View

@available(iOS 16.2, *)
struct TrainLockScreenView: View {
    let attributes: TrainTrackingAttributes
    let state: TrainTrackingAttributes.ContentState

    private var isDelayed: Bool { state.delayMinutes > 0 }
    private var statusText: String {
        switch state.status {
        case "completed": return "Journey Completed"
        case "arrived": return "At \(state.currentStation ?? "Station")"
        case "running":
            if let next = state.nextStation, !next.isEmpty {
                return "Next: \(next)"
            }
            return "Train is running"
        default: return "Yet to start"
        }
    }

    var body: some View {
        if isDelayed {
            delayedLayout
        } else {
            normalLayout
        }
    }

    // MARK: Normal Layout

    private var normalLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Status + Train badge
            HStack {
                Text(statusText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                Spacer()
                // Train badge
                Text("\(attributes.trainNumber)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black)
                    .cornerRadius(10)
            }

            // Row 2: Route with progress
            routeBar

            // Row 3: Meta info (platform, ETA, delay)
            HStack(spacing: 8) {
                if let platform = state.platform {
                    metaPill(text: "P\(platform)", bg: T.yellowPill, fg: T.yellowPillText)
                }
                if let eta = state.destinationArrival, !eta.isEmpty {
                    metaPill(text: "ETA \(eta)", bg: T.bluePill, fg: T.bluePillText)
                }
                if let updated = state.lastUpdated, !updated.isEmpty {
                    Spacer()
                    Text("Updated \(updated)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(T.subtitleColor)
                }
            }
        }
    }

    // MARK: Delayed Layout

    private var delayedLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Delay info + Train badge
            HStack {
                HStack(spacing: 6) {
                    Text("Late by \(delayText)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(T.delayTextLight)
                }
                Spacer()
                Text("\(attributes.trainNumber)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(T.delayTextLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(10)
            }

            // Row 2: Status text
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(T.delayTextLight.opacity(0.8))

            // Row 3: Route with progress
            routeBarDelayed

            // Row 4: Meta info
            HStack(spacing: 8) {
                if let platform = state.platform {
                    metaPill(text: "P\(platform)", bg: T.yellowPill, fg: T.yellowPillText)
                }
                if let eta = state.destinationArrival, !eta.isEmpty {
                    metaPill(text: "ETA \(eta)", bg: Color.white.opacity(0.2), fg: T.delayTextLight)
                }
                if let updated = state.lastUpdated, !updated.isEmpty {
                    Spacer()
                    Text("Updated \(updated)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(T.delayTextLight.opacity(0.6))
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [T.delayGradientStart, T.delayGradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(17)
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(T.delayBorder, lineWidth: 5)
        )
    }

    // MARK: Helpers

    private var delayText: String {
        let hrs = state.delayMinutes / 60
        let mins = state.delayMinutes % 60
        if hrs > 0 && mins > 0 {
            return "\(hrs)h \(mins)m"
        } else if hrs > 0 {
            return "\(hrs)h"
        } else {
            return "\(mins)m"
        }
    }

    private var routeBar: some View {
        HStack(spacing: 8) {
            Text(attributes.originCode)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.black)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(T.routeBg)
                        .frame(height: 4)
                    Capsule()
                        .fill(T.greenProgress)
                        .frame(width: max(0, geo.size.width * CGFloat(state.progress) / 100.0), height: 4)

                    // Train icon at progress point
                    Image(systemName: "tram.fill")
                        .font(.system(size: 10))
                        .foregroundColor(T.greenProgress)
                        .offset(x: max(0, geo.size.width * CGFloat(state.progress) / 100.0 - 5))
                }
            }
            .frame(height: 14)

            Text(attributes.destinationCode)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(T.routeBg)
        .cornerRadius(20)
    }

    private var routeBarDelayed: some View {
        HStack(spacing: 8) {
            Text(attributes.originCode)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(T.delayTextLight)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(T.orangeDelay)
                        .frame(width: max(0, geo.size.width * CGFloat(state.progress) / 100.0), height: 4)

                    Image(systemName: "tram.fill")
                        .font(.system(size: 10))
                        .foregroundColor(T.orangeDelay)
                        .offset(x: max(0, geo.size.width * CGFloat(state.progress) / 100.0 - 5))
                }
            }
            .frame(height: 14)

            Text(attributes.destinationCode)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(T.delayTextLight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
    }

    private func metaPill(text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .cornerRadius(8)
    }
}
