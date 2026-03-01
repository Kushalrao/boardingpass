import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Design Tokens

@available(iOS 16.2, *)
private enum C {
    // Blue pill (departure time / arrival time)
    static let bluePill = Color(red: 1/255, green: 107/255, blue: 229/255)         // #016be5
    static let bluePillText = Color(red: 205/255, green: 249/255, blue: 218/255)   // #cdf9da

    // Yellow pills (terminal & gate)
    static let yellowTerminal = Color(red: 255/255, green: 230/255, blue: 5/255)   // #ffe605
    static let yellowGate = Color(red: 255/255, green: 204/255, blue: 0)           // #ffcc00
    static let yellowPillText = Color(red: 109/255, green: 89/255, blue: 11/255)   // #6d590b

    // Delayed yellow pill
    static let delayPill = Color(red: 255/255, green: 230/255, blue: 5/255)        // #ffe605
    static let delayPillText = Color(red: 135/255, green: 110/255, blue: 12/255)   // #876e0c

    // Orange alert (gate change / diversion)
    static let orangePill = Color(red: 255/255, green: 70/255, blue: 0)            // #ff4600
    static let orangePillText = Color(red: 255/255, green: 234/255, blue: 226/255) // #ffeae2

    // Progress & route
    static let greenProgress = Color(red: 9/255, green: 200/255, blue: 66/255)     // #09c842
    static let routeBg = Color(red: 245/255, green: 245/255, blue: 240/255)        // #f5f5f0
    static let subtitleColor = Color.black.opacity(0.62)

    // Delay pill (dark gradient with red border)
    static let delayGradientStart = Color(red: 154/255, green: 4/255, blue: 75/255)   // #9a044b
    static let delayGradientEnd = Color(red: 81/255, green: 2/255, blue: 40/255)      // #510228
    static let delayBorder = Color(red: 255/255, green: 70/255, blue: 0)              // #ff4600
    static let delayPillTextLight = Color(red: 255/255, green: 234/255, blue: 226/255) // #ffeae2
    static let delayProgress = Color(red: 255/255, green: 70/255, blue: 0)            // #ff4600

    // Baggage (CSS yellow per Figma)
    static let baggageYellow = Color(red: 1.0, green: 1.0, blue: 0)         // #ffff00
}

// MARK: - Helpers

@available(iOS 16.2, *)
private func formatTime24(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

@available(iOS 16.2, *)
private func formatFlightNumber(_ raw: String) -> String {
    // "LH2738" → "LH 2738"
    guard let firstDigitIndex = raw.firstIndex(where: { $0.isNumber }) else { return raw }
    if firstDigitIndex == raw.startIndex { return raw }
    let code = raw[raw.startIndex..<firstDigitIndex]
    let number = raw[firstDigitIndex...]
    return "\(code) \(number)"
}

@available(iOS 16.2, *)
private func formatDuration(_ minutes: Int) -> String {
    if minutes <= 0 { return "" }
    if minutes < 60 { return "\(minutes)m" }
    let h = minutes / 60
    let m = minutes % 60
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

// MARK: - Main Widget

@available(iOS 16.2, *)
struct FlightActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightTrackingAttributes.self) { context in
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
                // EXPANDED
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.flightNumber)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let gate = context.state.departureGate {
                        Text(gate)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(C.yellowGate)
                            .foregroundColor(C.yellowPillText)
                            .cornerRadius(8)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "airplane")
                                .font(.system(size: 10, weight: .bold))
                            Text("AIRTIME")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        // Flight route row
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(context.attributes.originAirport)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Text(formatTime24(context.state.estimatedDeparture))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(diTimeColor(context.state, forDeparture: true))
                            }
                            .fixedSize()

                            // Progress capsule
                            if context.state.progress > 0
                                && context.state.progress < 100
                                && context.state.estimatedArrival > context.state.estimatedDeparture
                            {
                                ProgressView(
                                    timerInterval: context.state.estimatedDeparture...context.state.estimatedArrival,
                                    countsDown: false
                                ) { EmptyView() } currentValueLabel: { EmptyView() }
                                .progressViewStyle(.linear)
                                .tint(C.greenProgress)
                                .scaleEffect(y: 2.0, anchor: .center)
                                .frame(height: 8)
                                .clipShape(Capsule())
                                .padding(.horizontal, 8)
                            } else {
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.15))
                                            .frame(height: 8)
                                        Capsule()
                                            .fill(C.greenProgress)
                                            .frame(width: max(8, w * CGFloat(context.state.progress) / 100.0), height: 8)
                                    }
                                    .frame(maxHeight: .infinity)
                                }
                                .padding(.horizontal, 8)
                            }

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(context.attributes.destinationAirport)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Text(formatTime24(context.state.estimatedArrival))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(diTimeColor(context.state, forDeparture: false))
                            }
                            .fixedSize()
                        }

                        // Status row
                        HStack {
                            Text(diStatusText(context.state))
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            if context.state.status == "In Flight" {
                                let minutes = Int(context.state.estimatedArrival.timeIntervalSinceNow / 60)
                                if minutes > 0 {
                                    Text(formatDuration(minutes))
                                        .font(.system(size: 10, weight: .medium))
                                }
                            }
                        }
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Leading: always just the airport code
                let st = context.state
                let attr = context.attributes
                Text(st.status == "Landed" ? attr.destinationAirport : attr.originAirport)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.62))
                    .tracking(0.45)
            } compactTrailing: {
                // Trailing: contextual pill (priority: landed→belt, delay→time, gate, terminal, countdown)
                let st = context.state
                let attr = context.attributes
                if st.status == "Landed" {
                    if let belt = st.baggageBelt, !belt.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "suitcase.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(belt)
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(C.yellowPillText)
                        .padding(.horizontal, 7)
                        .frame(height: 25)
                        .background(C.baggageYellow)
                        .clipShape(Capsule())
                    }
                } else if st.delayMinutes > 0 {
                    Text(formatTime24(st.estimatedDeparture))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(C.delayPillTextLight)
                        .padding(.horizontal, 7)
                        .frame(height: 25)
                        .background(
                            LinearGradient(
                                colors: [C.delayGradientStart, C.delayGradientEnd],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(C.delayBorder, lineWidth: 2))
                } else if let gate = st.departureGate, !gate.isEmpty {
                    Text(gate)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(C.yellowPillText)
                        .padding(.horizontal, 7)
                        .frame(height: 25)
                        .background(C.yellowGate)
                        .clipShape(Capsule())
                } else if let terminal = st.departureTerminal, !terminal.isEmpty {
                    Text("T\(terminal)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(C.yellowPillText)
                        .padding(.horizontal, 7)
                        .frame(height: 25)
                        .background(C.yellowTerminal)
                        .clipShape(Capsule())
                } else {
                    let arrival = st.estimatedArrival
                    let now = Date()
                    let remaining = arrival.timeIntervalSince(now)
                    if remaining > 0 {
                        let hours = Int(remaining) / 3600
                        let minutes = (Int(remaining) % 3600) / 60
                        let label = hours > 0 ? "\(hours) H" : "\(minutes) M"
                        Text(label)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(C.bluePillText)
                            .padding(.horizontal, 7)
                            .frame(height: 25)
                            .background(C.bluePill)
                            .clipShape(Capsule())
                    }
                }
            } minimal: {
                ZStack {
                    Circle()
                        .trim(from: 0, to: CGFloat(context.state.progress) / 100.0)
                        .stroke(diStatusColor(context.state), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(diStatusColor(context.state))
                }
            }
        }
    }

    // MARK: - Dynamic Island Helpers

    private func diStatusColor(_ state: FlightTrackingAttributes.ContentState) -> Color {
        switch state.status {
        case "Cancelled": return .red
        case "Diverted": return .orange
        default: return state.delayMinutes > 0 ? .orange : C.greenProgress
        }
    }

    private func diTimeColor(_ state: FlightTrackingAttributes.ContentState, forDeparture: Bool) -> Color {
        switch state.status {
        case "Cancelled": return .red
        case "Diverted": return .orange
        default:
            if state.delayMinutes > 0 && forDeparture { return .orange }
            return C.greenProgress
        }
    }

    private func diStatusText(_ state: FlightTrackingAttributes.ContentState) -> String {
        switch state.status {
        case "Cancelled": return "Cancelled"
        case "Diverted": return "Diverted"
        case "Landed": return "Landed"
        case "In Flight": return "In Flight"
        case "Delayed": return "Delayed \(state.delayMinutes)m"
        default:
            if state.delayMinutes > 0 { return "Delayed \(state.delayMinutes)m" }
            return "On Time"
        }
    }
}

// MARK: - Lock Screen View

@available(iOS 16.2, *)
struct FlightLockScreenView: View {
    let attributes: FlightTrackingAttributes
    let state: FlightTrackingAttributes.ContentState

    var body: some View {
        Group {
            switch state.status {
            case "Landed", "In Flight":
                ArrivedLayout(attributes: attributes, state: state)
            default:
                StandardLayout(attributes: attributes, state: state)
            }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 19)
    }
}

// MARK: - Standard Layout (Scheduled / Delayed / In Flight / Cancelled / Diverted / Boarding)
// Figma references: 66:2018 (pre flight start), 69:2067 (flight started)

@available(iOS 16.2, *)
private struct StandardLayout: View {
    let attributes: FlightTrackingAttributes
    let state: FlightTrackingAttributes.ContentState

    // Time pill styling (non-delayed states only — delayed uses DelayTimePill)
    private var pillBg: Color {
        switch state.status {
        case "Cancelled": return .red
        case "Diverted": return C.orangePill
        default: return C.bluePill
        }
    }

    private var pillText: Color {
        switch state.status {
        case "Cancelled": return .white
        case "Diverted": return C.orangePillText
        default: return C.bluePillText
        }
    }

    private var isDelayed: Bool { state.delayMinutes > 0 }

    private var titleText: String {
        switch state.status {
        case "Cancelled": return "Flight cancelled"
        case "Diverted":
            if let airport = state.diversionAirport {
                return "Diverted to \(airport)"
            }
            return "Flight diverted"
        case "Boarding": return "Boarding now"
        default:
            if isDelayed {
                return "Flight delayed"
            }
            return "Your flight is on time"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── ROW 1: Time pill + Title & airline info ──
            HStack(alignment: .top, spacing: 16) {
                // Departure time pill
                if isDelayed {
                    DelayTimePill(
                        scheduledTime: attributes.scheduledDeparture,
                        estimatedTime: state.estimatedDeparture
                    )
                } else {
                    Text(formatTime24(state.estimatedDeparture))
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .tracking(1.16)
                        .foregroundColor(pillText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(pillBg)
                        .cornerRadius(17)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Title
                    Text(titleText)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.black)
                        .tracking(0.63)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Airline badge
                    AirlineBadge(flightNumber: attributes.flightNumber)
                }

                Spacer(minLength: 0)
            }

            Spacer()

            // ── ROW 2: Route pill ──
            RoutePill(
                origin: attributes.originAirport,
                destination: attributes.destinationAirport,
                progress: state.progress,
                departureDate: state.estimatedDeparture,
                arrivalDate: state.estimatedArrival,
                isDelayed: isDelayed
            )

            // ── ROW 3: Meta pills + Arrival info (tight below route) ──
            HStack(spacing: 9) {
                if let terminal = state.departureTerminal, !terminal.isEmpty {
                    MetaPill(text: "T\(terminal)", bg: C.yellowTerminal, fg: C.yellowPillText)
                }

                if let gate = state.departureGate, !gate.isEmpty {
                    MetaPill(text: gate, bg: C.yellowGate, fg: C.yellowPillText)
                }

                Spacer(minLength: 0)

                if state.status != "Cancelled" {
                    Text("Arrival at \(formatTime24(state.estimatedArrival))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .tracking(0.42)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Arrived Layout (In Flight + Landed)
// Figma reference: 69:2099 (flight arrived / arrival-focused)

@available(iOS 16.2, *)
private struct ArrivedLayout: View {
    let attributes: FlightTrackingAttributes
    let state: FlightTrackingAttributes.ContentState

    private var isLanded: Bool { state.status == "Landed" }
    private var isDelayed: Bool { state.delayMinutes > 0 }

    private var titleText: String {
        if isLanded {
            return "Arrived in \(attributes.destinationCity)"
        }
        return isDelayed ? "Arriving late" : "Arrival in \(attributes.destinationCity)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── ROW 1: Title & airline (left) + Arrival time pill (right) ──
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.black)
                        .tracking(0.63)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Airline badge
                    AirlineBadge(flightNumber: attributes.flightNumber)
                }

                Spacer(minLength: 0)

                // Arrival time pill (on the right side)
                if isDelayed {
                    DelayTimePill(
                        scheduledTime: attributes.scheduledArrival,
                        estimatedTime: state.estimatedArrival
                    )
                } else {
                    Text(formatTime24(state.estimatedArrival))
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .tracking(1.16)
                        .foregroundColor(C.bluePillText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(C.bluePill)
                        .cornerRadius(17)
                }
            }

            Spacer()

            // ── ROW 2: Route pill ──
            RoutePill(
                origin: attributes.originAirport,
                destination: attributes.destinationAirport,
                progress: state.progress,
                departureDate: isLanded ? nil : state.estimatedDeparture,
                arrivalDate: isLanded ? nil : state.estimatedArrival,
                isDelayed: isDelayed
            )

            // ── ROW 3: Bottom info (tight below route) ──
            HStack(spacing: 9) {
                Spacer(minLength: 0)

                if let belt = state.baggageBelt, !belt.isEmpty {
                    Text("Baggage belt number")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .tracking(0.42)
                    BaggagePill(beltNumber: belt)
                }

                if let terminal = state.arrivalTerminal, !terminal.isEmpty {
                    MetaPill(text: "T\(terminal)", bg: C.yellowTerminal, fg: C.yellowPillText)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Reusable Components

@available(iOS 16.2, *)
private struct AirlineBadge: View {
    let flightNumber: String

    private var carrierCode: String {
        String(flightNumber.prefix(2)).uppercased()
    }

    var body: some View {
        HStack(spacing: 4) {
            // Airline logo — bundled asset or text fallback
            if let uiImage = UIImage(named: carrierCode) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(red: 230/255, green: 230/255, blue: 220/255))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text(carrierCode)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.black.opacity(0.5))
                    )
            }

            Text(formatFlightNumber(flightNumber))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .tracking(0.7)
        }
        .opacity(0.72)
    }
}

@available(iOS 16.2, *)
private struct RoutePill: View {
    let origin: String
    let destination: String
    let progress: Int
    var departureDate: Date? = nil
    var arrivalDate: Date? = nil
    var isDelayed: Bool = false

    private var progressColor: Color {
        isDelayed ? C.delayProgress : C.greenProgress
    }

    private var useAutoProgress: Bool {
        guard let dep = departureDate, let arr = arrivalDate else { return false }
        return progress > 0 && progress < 100 && arr > dep
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(origin)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(C.subtitleColor)
                .tracking(0.45)
                .fixedSize()
                .padding(.leading, 7)

            // Progress indicator area
            if progress == 0 {
                // Dot for pre-departure
                GeometryReader { _ in
                    HStack(spacing: 0) {
                        Circle()
                            .fill(progressColor)
                            .frame(width: 15, height: 15)
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 9)
            } else if useAutoProgress {
                // Auto-animating progress — fills on-device without pushes
                ProgressView(
                    timerInterval: departureDate!...arrivalDate!,
                    countsDown: false
                ) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(progressColor)
                .scaleEffect(y: 3.75, anchor: .center)
                .frame(height: 15)
                .clipShape(Capsule())
                .padding(.horizontal, 9)
            } else {
                // Static progress bar (arrived or fallback)
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(progressColor)
                            .frame(
                                width: max(15, totalWidth * CGFloat(progress) / 100.0),
                                height: 15
                            )
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 9)
            }

            Text(destination)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(C.subtitleColor)
                .tracking(0.45)
                .fixedSize()
                .padding(.trailing, 7)
        }
        .padding(.vertical, 5)
        .background(C.routeBg)
        .clipShape(Capsule())
    }
}

@available(iOS 16.2, *)
private struct MetaPill: View {
    let text: String
    let bg: Color
    let fg: Color

    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .heavy, design: .rounded))
            .foregroundColor(fg)
            .padding(.horizontal, 9)
            .frame(height: 33)
            .background(bg)
            .clipShape(Capsule())
    }
}

@available(iOS 16.2, *)
private struct BaggagePill: View {
    let beltNumber: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(beltNumber)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
        }
        .foregroundColor(C.yellowPillText)
        .padding(.horizontal, 9)
        .frame(height: 33)
        .background(C.baggageYellow)
        .clipShape(Capsule())
    }
}

@available(iOS 16.2, *)
private struct DelayTimePill: View {
    let scheduledTime: Date
    let estimatedTime: Date

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            // Original time — struck through
            Text(formatTime24(scheduledTime))
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .tracking(0.76)
                .strikethrough(true, color: C.delayPillTextLight)
            // New estimated time
            Text(formatTime24(estimatedTime))
                .font(.system(size: 29, weight: .heavy, design: .rounded))
                .tracking(1.16)
        }
        .foregroundColor(C.delayPillTextLight)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [C.delayGradientStart, C.delayGradientEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(17)
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(C.delayBorder, lineWidth: 5)
        )
    }
}

// MARK: - Widget Bundle

@available(iOS 16.2, *)
@main
struct FlightTrackingWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlightActivityWidget()
        TrainActivityWidget()
    }
}
