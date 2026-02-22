import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Banner Config

@available(iOS 16.2, *)
struct BannerConfig {
    let icon: String
    let text: String
    let detail: String
    let backgroundColor: Color
    let foregroundColor: Color
}

// MARK: - Main Widget

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
                // EXPANDED Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.flightNumber)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let gate = context.state.departureGate {
                        HStack(spacing: 3) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 10, weight: .medium))
                            Text(gate)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "airplane")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                            Text("AIRTIME")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        // Main flight row
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(context.attributes.originAirport)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Text(Self.formatTime(date: context.state.estimatedDeparture))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Self.timeColor(state: context.state, forDeparture: true))
                            }
                            .fixedSize()

                            InlineFlightPathView(
                                progress: context.state.progress,
                                lightBackground: false
                            )
                            .padding(.horizontal, 4)

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(context.attributes.destinationAirport)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Text(Self.formatTime(date: context.state.estimatedArrival))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Self.timeColor(state: context.state, forDeparture: false))
                            }
                            .fixedSize()
                        }

                        // Status banner
                        let banner = Self.bannerConfig(attributes: context.attributes, state: context.state)
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: banner.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(banner.text)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Spacer()
                            if !banner.detail.isEmpty {
                                Text(banner.detail)
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(banner.backgroundColor.opacity(0.85))
                        .foregroundColor(banner.foregroundColor)
                        .cornerRadius(8)
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
                        .stroke(Self.statusColor(context.state), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Self.statusColor(context.state))
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
                        .stroke(Self.statusColor(context.state), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Self.statusColor(context.state))
                }
            }
        }
    }

    // MARK: - Time Formatting

    static func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter.string(from: date)
    }

    // MARK: - Color Helpers

    static func timeColor(state: FlightTrackingAttributes.ContentState, forDeparture: Bool, lightBackground: Bool = false) -> Color {
        switch state.status {
        case "Cancelled":
            return .red
        case "Diverted":
            return .orange
        case "Delayed":
            return forDeparture ? .orange : .green
        default:
            if state.delayMinutes > 0 && forDeparture {
                return .orange
            }
            return .green
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

    // MARK: - Status Text Helpers

    static func departureStatusText(_ state: FlightTrackingAttributes.ContentState) -> String {
        switch state.status {
        case "Cancelled":
            return "Cancelled"
        case "Diverted":
            return "Diverted"
        case "Delayed":
            return "Delayed \(state.delayMinutes)m"
        default:
            if state.delayMinutes > 0 {
                return "Delayed \(state.delayMinutes)m"
            }
            return "On Time"
        }
    }

    static func arrivalStatusText(_ state: FlightTrackingAttributes.ContentState) -> String {
        switch state.status {
        case "Cancelled":
            return "Cancelled"
        case "Diverted":
            if let airport = state.diversionAirport {
                return "→ \(airport)"
            }
            return "Diverted"
        case "Landed":
            return "Landed"
        default:
            return "On Time"
        }
    }

    static func arrivalStatusColor(_ state: FlightTrackingAttributes.ContentState) -> Color {
        switch state.status {
        case "Cancelled":
            return .red
        case "Diverted":
            return .orange
        case "Landed":
            return .blue
        default:
            return .green
        }
    }

    // MARK: - Banner Config

    static func bannerConfig(attributes: FlightTrackingAttributes, state: FlightTrackingAttributes.ContentState) -> BannerConfig {
        switch state.status {
        case "Cancelled":
            return BannerConfig(
                icon: "xmark.octagon.fill",
                text: "Cancelled",
                detail: "",
                backgroundColor: .red,
                foregroundColor: .white
            )

        case "Diverted":
            let dest = state.diversionAirport ?? "Unknown"
            return BannerConfig(
                icon: "exclamationmark.triangle.fill",
                text: "Diverted to \(dest)",
                detail: "",
                backgroundColor: .orange,
                foregroundColor: .black
            )

        case "Landed":
            let beltText = state.baggageBelt.map { "Baggage Belt \($0)" } ?? "Arrived"
            return BannerConfig(
                icon: "airplane.arrival",
                text: "Landed",
                detail: beltText,
                backgroundColor: .blue,
                foregroundColor: .white
            )

        case "In Flight":
            let minutes = Int(state.estimatedArrival.timeIntervalSinceNow / 60)
            let landingText: String
            if minutes <= 0 {
                landingText = "Landing now"
            } else if minutes < 60 {
                landingText = "Landing in \(minutes)m"
            } else {
                let h = minutes / 60
                let m = minutes % 60
                landingText = m == 0 ? "Landing in \(h)h" : "Landing in \(h)h \(m)m"
            }
            return BannerConfig(
                icon: "airplane",
                text: "In Flight",
                detail: landingText,
                backgroundColor: .green,
                foregroundColor: .white
            )

        case "Boarding":
            let gateText = state.departureGate.map { "Gate \($0)" } ?? "Boarding"
            return BannerConfig(
                icon: "figure.walk",
                text: gateText,
                detail: "Boarding",
                backgroundColor: Color(red: 1.0, green: 0.8, blue: 0.0),
                foregroundColor: .black
            )

        case "Delayed":
            let newTime = formatTime(date: state.estimatedDeparture)
            return BannerConfig(
                icon: "clock.fill",
                text: "Delayed \(state.delayMinutes) min",
                detail: "New departure \(newTime)",
                backgroundColor: .orange,
                foregroundColor: .black
            )

        default: // "Scheduled" or unknown
            if state.delayMinutes > 0 {
                let newTime = formatTime(date: state.estimatedDeparture)
                return BannerConfig(
                    icon: "clock.fill",
                    text: "Delayed \(state.delayMinutes) min",
                    detail: "New departure \(newTime)",
                    backgroundColor: .orange,
                    foregroundColor: .black
                )
            } else if let gate = state.departureGate {
                let minutesToDep = Int(state.estimatedDeparture.timeIntervalSinceNow / 60)
                let timeText: String
                if minutesToDep <= 0 {
                    timeText = "Departing now"
                } else if minutesToDep < 60 {
                    timeText = "Gate Departure in \(minutesToDep)m"
                } else {
                    let h = minutesToDep / 60
                    let m = minutesToDep % 60
                    timeText = m == 0 ? "Gate Departure in \(h)h" : "Gate Departure in \(h)h \(m)m"
                }
                return BannerConfig(
                    icon: "airplane.departure",
                    text: "Gate \(gate)",
                    detail: timeText,
                    backgroundColor: Color(red: 1.0, green: 0.8, blue: 0.0),
                    foregroundColor: .black
                )
            } else {
                let minutesToDep = Int(state.estimatedDeparture.timeIntervalSinceNow / 60)
                let timeText: String
                if minutesToDep <= 0 {
                    timeText = "Departing now"
                } else if minutesToDep < 60 {
                    timeText = "Departure in \(minutesToDep)m"
                } else {
                    let h = minutesToDep / 60
                    let m = minutesToDep % 60
                    timeText = m == 0 ? "Departure in \(h)h" : "Departure in \(h)h \(m)m"
                }
                return BannerConfig(
                    icon: "airplane.departure",
                    text: "Scheduled",
                    detail: timeText,
                    backgroundColor: Color(.systemGray5),
                    foregroundColor: .black.opacity(0.7)
                )
            }
        }
    }
}

// MARK: - Inline Flight Path (dots + airplane)

@available(iOS 16.2, *)
struct InlineFlightPathView: View {
    let progress: Int
    var lightBackground: Bool = false

    private var dotColor: Color { lightBackground ? .black.opacity(0.2) : .white.opacity(0.3) }
    private var activeColor: Color { .green }
    private var planeColor: Color { lightBackground ? .black : .white }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let centerY = h / 2
            let pct = CGFloat(progress) / 100.0
            let margin: CGFloat = 6
            let pathStart = margin
            let pathEnd = w - margin
            let pathWidth = pathEnd - pathStart
            let planeX = pathStart + pct * pathWidth

            // Dots
            let dotSpacing: CGFloat = 7
            let dotRadius: CGFloat = 1.5
            let dotCount = max(1, Int(pathWidth / dotSpacing))

            Canvas { ctx, size in
                for i in 0..<dotCount {
                    let x = pathStart + CGFloat(i) * dotSpacing
                    let isBehind = x < planeX - 8
                    let color = isBehind ? activeColor : dotColor
                    let rect = CGRect(
                        x: x - dotRadius,
                        y: centerY - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    ctx.fill(Circle().path(in: rect), with: .color(color))
                }
            }

            // Airplane
            Image(systemName: "airplane")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(planeColor)
                .position(x: planeX, y: centerY)
        }
        .frame(height: 18)
    }
}

// MARK: - Lock Screen View

@available(iOS 16.2, *)
struct FlightLockScreenView: View {
    let attributes: FlightTrackingAttributes
    let state: FlightTrackingAttributes.ContentState

    var body: some View {
        VStack(spacing: 6) {
            // ── HEADER ROW ──
            HStack {
                Text(attributes.flightNumber)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.6))

                Spacer()

                if let gate = state.departureGate {
                    HStack(spacing: 3) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 10, weight: .medium))
                        Text(gate)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.07))
                    .foregroundColor(.black.opacity(0.7))
                    .cornerRadius(6)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "airplane")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black.opacity(0.3))
                        Text("AIRTIME")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black.opacity(0.3))
                    }
                }
            }

            // ── MAIN FLIGHT ROW ──
            HStack(spacing: 0) {
                // Departure side
                HStack(spacing: 4) {
                    Text(attributes.originAirport)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                    Text(FlightActivityWidget.formatTime(date: state.estimatedDeparture))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FlightActivityWidget.timeColor(state: state, forDeparture: true, lightBackground: true))
                }
                .fixedSize()

                // Dotted path
                InlineFlightPathView(progress: state.progress, lightBackground: true)
                    .padding(.horizontal, 4)

                // Arrival side
                HStack(spacing: 4) {
                    Text(FlightActivityWidget.formatTime(date: state.estimatedArrival))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FlightActivityWidget.timeColor(state: state, forDeparture: false, lightBackground: true))
                    Text(attributes.destinationAirport)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                }
                .fixedSize()
            }

            // ── STATUS ROW ──
            HStack {
                // Departure status
                HStack(spacing: 0) {
                    if let terminal = state.departureTerminal, !terminal.isEmpty {
                        Text("T\(terminal)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                        Text(" \u{00B7} ")
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.3))
                    }
                    Text(FlightActivityWidget.departureStatusText(state))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FlightActivityWidget.statusColor(state))
                }

                Spacer()

                // Arrival status
                HStack(spacing: 0) {
                    if let terminal = state.arrivalTerminal, !terminal.isEmpty {
                        Text("T\(terminal)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                        Text(" \u{00B7} ")
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.3))
                    }
                    Text(FlightActivityWidget.arrivalStatusText(state))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FlightActivityWidget.arrivalStatusColor(state))
                }
            }

            // ── CONTEXTUAL BANNER ──
            let banner = FlightActivityWidget.bannerConfig(attributes: attributes, state: state)
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: banner.icon)
                        .font(.system(size: 12, weight: .bold))
                    Text(banner.text)
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                if !banner.detail.isEmpty {
                    Text(banner.detail)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(banner.backgroundColor)
            .foregroundColor(banner.foregroundColor)
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
