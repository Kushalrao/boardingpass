import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
struct FlightActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightTrackingAttributes.self) { context in
            // LOCK SCREEN / STANDBY presentation
            ZStack {
                Color.white
                FlightLockScreenView(
                    attributes: context.attributes,
                    state: context.state
                )
            }
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED Dynamic Island — Flighty style
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.flightNumber)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "airplane")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text("AIRTIME")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        // Airport codes with curved flight path
                        FlightPathView(
                            origin: context.attributes.originAirport,
                            destination: context.attributes.destinationAirport,
                            progress: context.state.progress
                        )

                        // Status row
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.statusText(context.state))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Self.statusColor(context.state))
                                Text(Self.subtitleText(context.state, arrival: context.state.estimatedArrival))
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            Spacer()

                            if let belt = context.state.baggageBelt {
                                HStack(spacing: 3) {
                                    Image(systemName: "suitcase.fill")
                                        .font(.system(size: 10))
                                    Text(belt)
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.orange)
                                .foregroundColor(.black)
                                .cornerRadius(6)
                            } else if let gate = context.state.departureGate {
                                HStack(spacing: 3) {
                                    Image(systemName: "door.left.hand.open")
                                        .font(.system(size: 10))
                                    Text(gate)
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Circular progress with airplane
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    Circle()
                        .trim(from: 0, to: CGFloat(context.state.progress) / 100.0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
            } compactTrailing: {
                Text("To \(context.attributes.destinationAirport)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: 60)
            } minimal: {
                ZStack {
                    Circle()
                        .trim(from: 0, to: CGFloat(context.state.progress) / 100.0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - Helpers

    static func statusText(_ state: FlightTrackingAttributes.ContentState) -> String {
        switch state.status {
        case "Cancelled":
            return "Cancelled"
        case "Diverted":
            if let airport = state.diversionAirport {
                return "Diverted to \(airport)"
            }
            return "Diverted"
        case "Landed":
            return "Landed"
        default:
            if state.delayMinutes > 0 {
                return "Delayed \(state.delayMinutes)m"
            }
            return "On Time"
        }
    }

    static func subtitleText(_ state: FlightTrackingAttributes.ContentState, arrival: Date) -> String {
        switch state.status {
        case "Cancelled":
            return "Flight cancelled"
        case "Landed":
            if let belt = state.baggageBelt {
                return "Baggage at belt \(belt)"
            }
            return "Arrived"
        case "Diverted":
            return "Check with airline"
        default:
            let minutes = Int(arrival.timeIntervalSinceNow / 60)
            if minutes <= 0 {
                return "Arriving now"
            } else if minutes < 60 {
                return "Landing in \(minutes)m"
            } else {
                let hours = minutes / 60
                let mins = minutes % 60
                if mins == 0 {
                    return "Landing in \(hours)h"
                }
                return "Landing in \(hours)h \(mins)m"
            }
        }
    }

    static func statusColor(_ state: FlightTrackingAttributes.ContentState) -> Color {
        switch state.status {
        case "Cancelled":
            return .red
        case "Diverted":
            return .orange
        default:
            if state.delayMinutes > 0 {
                return .orange
            }
            return .green
        }
    }
}

// MARK: - Curved Flight Path (Expanded Dynamic Island + Lock Screen)

@available(iOS 16.2, *)
struct FlightPathView: View {
    let origin: String
    let destination: String
    let progress: Int
    var lightBackground: Bool = false

    private var primaryColor: Color { lightBackground ? .black : .white }
    private var dottedLineColor: Color { lightBackground ? .black.opacity(0.2) : .white.opacity(0.4) }

    var body: some View {
        HStack(spacing: 0) {
            // Origin airport code
            Text(origin)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(primaryColor)
                .fixedSize()

            // Flight path between codes
            GeometryReader { geo in
                let w = geo.size.width
                let dotSize: CGFloat = 16
                let planeSize: CGFloat = 13
                let margin: CGFloat = 2
                let pathStart = margin + dotSize / 2
                let pathEnd = w - margin - dotSize / 2
                let pathWidth = pathEnd - pathStart
                let centerY: CGFloat = geo.size.height / 2
                let arcHeight: CGFloat = 18
                let pct = CGFloat(progress) / 100.0

                // Departure dot with arrow
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: dotSize, height: dotSize)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                }
                .position(x: pathStart, y: centerY)

                // Arrival dot with arrow
                ZStack {
                    Circle()
                        .fill(progress >= 95 ? Color.green : Color.green.opacity(0.5))
                        .frame(width: dotSize, height: dotSize)
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                }
                .position(x: pathEnd, y: centerY)

                // Green solid line (completed portion)
                if pct > 0 {
                    Path { path in
                        let steps = max(1, Int(pct * 40))
                        for i in 0...steps {
                            let t = CGFloat(i) / 40.0
                            let x = pathStart + t * pathWidth
                            let y = centerY - sin(t * .pi) * arcHeight
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }

                // Dotted line (remaining portion)
                Path { path in
                    let startT = pct
                    let steps = max(1, Int((1 - pct) * 40))
                    for i in 0...steps {
                        let t = startT + CGFloat(i) / 40.0 * (1 - startT)
                        let x = pathStart + t * pathWidth
                        let y = centerY - sin(t * .pi) * arcHeight
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(dottedLineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))

                // Airplane ON the path
                let planeX = pathStart + pct * pathWidth
                let planeY = centerY - sin(pct * .pi) * arcHeight
                // Calculate angle of the arc at this point for rotation
                let dx: CGFloat = 1.0
                let nextT = min(1.0, pct + 0.02)
                let prevT = max(0.0, pct - 0.02)
                let dy = sin(nextT * .pi) - sin(prevT * .pi)
                let angle = atan2(-dy * arcHeight, (nextT - prevT) * pathWidth)
                Image(systemName: "airplane")
                    .font(.system(size: planeSize, weight: .bold))
                    .foregroundColor(primaryColor)
                    .rotationEffect(.degrees(Double(angle) * 180 / .pi))
                    .position(x: planeX, y: planeY)
            }

            // Destination airport code
            Text(destination)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(primaryColor)
                .fixedSize()
        }
        .frame(height: 40)
    }
}

// MARK: - Lock Screen View (Flighty style)

@available(iOS 16.2, *)
struct FlightLockScreenView: View {
    let attributes: FlightTrackingAttributes
    let state: FlightTrackingAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            // Header: flight number + AIRTIME branding
            HStack {
                Text(attributes.flightNumber)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black.opacity(0.7))

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "airplane")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black.opacity(0.35))
                    Text("AIRTIME")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black.opacity(0.35))
                }
            }

            // Airport codes with curved flight path
            FlightPathView(
                origin: attributes.originAirport,
                destination: attributes.destinationAirport,
                progress: state.progress,
                lightBackground: true
            )

            // Status row
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(FlightActivityWidget.statusText(state))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(FlightActivityWidget.statusColor(state))
                    Text(FlightActivityWidget.subtitleText(state, arrival: state.estimatedArrival))
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.45))
                }

                Spacer()

                HStack(spacing: 6) {
                    if let terminal = state.arrivalTerminal {
                        HStack(spacing: 3) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 9))
                            Text("T\(terminal)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(7)
                    }

                    if let belt = state.baggageBelt {
                        HStack(spacing: 3) {
                            Image(systemName: "suitcase.fill")
                                .font(.system(size: 9))
                            Text(belt)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(7)
                    } else if let gate = state.arrivalGate {
                        HStack(spacing: 3) {
                            Image(systemName: "door.left.hand.open")
                                .font(.system(size: 9))
                            Text(gate)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(7)
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Widget Bundle

@available(iOS 16.2, *)
@main
struct FlightTrackingWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlightActivityWidget()
    }
}
