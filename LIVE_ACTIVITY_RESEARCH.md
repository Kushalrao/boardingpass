# Live Activities & Real-Time Persistent UI — Research

> Research on iOS Live Activities, Android equivalents, and implementation strategy for Airtime.

---

## 1. iOS LIVE ACTIVITIES

### What Are They?

Live Activities are a dedicated real-time UI surface introduced in iOS 16.1. They are NOT notifications — they are a distinct system primitive designed for time-sensitive, ongoing events that users can track without opening the app.

### Where They Appear (5 Surfaces)

| Surface | Device | Behavior |
|---------|--------|----------|
| **Lock Screen** | All iPhones (iOS 16.1+) | Banner-like card at bottom, max height 160pt. Visible when phone is locked. |
| **Dynamic Island** | iPhone 14 Pro and later | Compact, expanded, and minimal presentations around the pill-shaped camera cutout. |
| **StandBy Mode** | iPhones (iOS 17+) | Full-screen display when device is in landscape and charging. Layout scaled up 200%. |
| **Apple Watch** | watchOS 10+ (via Smart Stack) | Mirrored from iPhone when using the same iCloud account. |
| **CarPlay** | CarPlay-enabled vehicles | Displays relevant Live Activities from compatible apps. |

On devices without Dynamic Island (iPhone 14 and earlier, SE), Live Activities still appear on the Lock Screen.

### Core Frameworks

- **ActivityKit** — Lifecycle management. Used in the **main app target** to start, update, and end Live Activities and manage push tokens.
- **WidgetKit** — UI rendering. Used in a **Widget Extension target** to define visual presentation using SwiftUI via `ActivityConfiguration`.

### Data Model: ActivityAttributes Protocol

Every Live Activity requires a data model conforming to `ActivityAttributes`:

```swift
struct FlightTrackingAttributes: ActivityAttributes {
    // STATIC DATA — set once when the activity starts, never changes
    var flightNumber: String
    var airline: String
    var departureAirport: String
    var arrivalAirport: String

    // DYNAMIC DATA — changes over the lifetime of the activity
    public struct ContentState: Codable, Hashable {
        var status: String           // "Scheduled", "Boarding", "In Flight", "Landed"
        var departureGate: String?
        var estimatedDeparture: Date
        var estimatedArrival: Date
        var delayMinutes: Int
    }
}
```

Key rules:
- `ActivityAttributes` holds **static** data (immutable after creation)
- The nested `ContentState` struct holds **dynamic** data (updated via ActivityKit or push)
- Both must conform to `Codable` and `Hashable`
- **Combined size cannot exceed 4 KB**

### Widget Extension UI (SwiftUI)

The UI is declared in the Widget Extension using `ActivityConfiguration`:

```swift
struct FlightActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightTrackingAttributes.self) { context in
            // LOCK SCREEN / STANDBY / BANNER presentation
            FlightLockScreenView(context: context)
                .activityBackgroundTint(.white)
                .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED presentation regions
                DynamicIslandExpandedRegion(.leading) { /* departure info */ }
                DynamicIslandExpandedRegion(.trailing) { /* arrival info */ }
                DynamicIslandExpandedRegion(.center) { /* flight number + status */ }
                DynamicIslandExpandedRegion(.bottom) { /* progress bar */ }
            } compactLeading: {
                // COMPACT leading — icon or small image
                Image(systemName: "airplane.departure")
            } compactTrailing: {
                // COMPACT trailing — short text or timer
                Text(context.state.estimatedArrival, style: .timer)
            } minimal: {
                // MINIMAL — tiny presentation when multiple activities compete
                Image(systemName: "airplane")
            }
        }
    }
}
```

### Lifecycle: Start, Update, End

**Starting (app must be in foreground, unless using push-to-start on iOS 17.2+):**
```swift
let attributes = FlightTrackingAttributes(flightNumber: "LX147", ...)
let initialState = FlightTrackingAttributes.ContentState(status: "Scheduled", ...)
let activity = try Activity<FlightTrackingAttributes>.request(
    attributes: attributes,
    content: .init(state: initialState, staleDate: nil),
    pushType: .token   // Enable remote push updates
)
```

**Updating (foreground or background):**
```swift
let updatedState = FlightTrackingAttributes.ContentState(status: "Boarding", ...)
await activity.update(ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(900)))
```

**Ending:**
```swift
await activity.end(
    ActivityContent(state: finalState, staleDate: nil),
    dismissalPolicy: .immediate  // or .default (stays 4hrs) or .after(Date())
)
```

### Push Token Mechanism (Remote Updates)

Each Live Activity gets its **own unique APNs push token**, separate from the app's regular push token.

**Flow:**
1. App requests a Live Activity with `pushType: .token`
2. ActivityKit obtains a unique push token from APNs for that specific activity
3. App sends the token to your backend server
4. Server uses the token to send updates via APNs (HTTP/2, token-based JWT auth only)
5. APNs delivers the payload to the device and wakes the Widget Extension to re-render

**Important:** The push token **can change** during the activity's lifetime. You must observe `pushTokenUpdates` and update your server.

```swift
Task {
    for await pushToken in activity.pushTokenUpdates {
        let tokenString = pushToken.reduce("") { $0 + String(format: "%02x", $1) }
        // Send tokenString to your server
    }
}
```

**Push-to-Start tokens (iOS 17.2+):**
```swift
Task {
    for await pushToken in Activity<FlightTrackingAttributes>.pushToStartTokenUpdates {
        let tokenString = pushToken.reduce("") { $0 + String(format: "%02x", $1) }
        // Send to server — server can use this to START an activity remotely
    }
}
```

### APNs Payload Format

**Required HTTP/2 Headers:**

| Header | Value |
|--------|-------|
| `apns-push-type` | `liveactivity` |
| `apns-topic` | `<bundleID>.push-type.liveactivity` |
| `apns-priority` | `5` (low/batched) or `10` (high/immediate) |

**Update payload:**
```json
{
  "aps": {
    "timestamp": 1705560370,
    "event": "update",
    "content-state": {
      "status": "Boarding",
      "departureGate": "B22",
      "estimatedDeparture": 1705561570,
      "estimatedArrival": 1705594170,
      "delayMinutes": 0
    },
    "stale-date": 1705567570
  }
}
```

**Start payload (push-to-start, iOS 17.2+):**
```json
{
  "aps": {
    "timestamp": 1705547770,
    "event": "start",
    "attributes-type": "FlightTrackingAttributes",
    "attributes": {
      "flightNumber": "LX147",
      "airline": "Swiss",
      "departureAirport": "DEL",
      "arrivalAirport": "ZRH"
    },
    "content-state": {
      "status": "Scheduled",
      "departureGate": null,
      "estimatedDeparture": 1705549570,
      "estimatedArrival": 1705582170,
      "delayMinutes": 0
    },
    "alert": {
      "title": "Flight LX147 Tracked",
      "body": "Delhi to Zurich — departing at 01:45 AM"
    }
  }
}
```

**End payload:**
```json
{
  "aps": {
    "timestamp": 1705560370,
    "event": "end",
    "content-state": {
      "status": "Landed",
      "delayMinutes": 0
    },
    "dismissal-date": 1705560400
  }
}
```

### Broadcast Push (iOS 18+)

Instead of sending individual pushes per device token, you create a **channel** identified by a unique channel ID. Users subscribe to a channel. You send **one** push to APNs and it broadcasts to all subscribers. Useful for shared events like sports scores.

### Dynamic Island — 3 Presentations

**1. Compact (default single-activity view)**
```
[compact leading] ●●●●●●● [compact trailing]
                  (camera)
```
- Leading: icon or small image
- Trailing: short text, timer, or small graphic

**2. Minimal (multi-activity competition)**
```
●●●●●●● [minimal]
(camera)  ●
```
- Single small element (icon or tiny text)
- System decides which activity to show

**3. Expanded (user long-presses)**
```
┌─────────────────────────────────────┐
│  [leading]    ●●●●●●●   [trailing]  │
│               (camera)               │
│              [center]                │
│              [bottom]                │
└─────────────────────────────────────┘
```
- Full canvas with 4 regions
- Best for progress bars, detailed info, action buttons (via App Intents)

### Hard Limits

| Constraint | Value |
|------------|-------|
| Max simultaneous activities per app | 5 |
| Max data size (static + dynamic) | 4 KB |
| Lock Screen view max height | 160 points |
| Active duration | Up to 8 hours (system auto-ends) |
| Post-end Lock Screen retention | Up to 4 additional hours |
| Total maximum visibility | ~12 hours (8 active + 4 post-end) |

### Update Frequency

- iOS 18+: Updates render every 5-15 seconds (throttled for battery)
- Priority 10 (high): Immediate delivery, subject to dynamic per-device budget
- Priority 5 (low): Batched delivery, doesn't consume high-priority budget
- `NSSupportsLiveActivitiesFrequentUpdates = YES` in Info.plist increases budget
- SwiftUI `Text(date, style: .timer)` updates automatically without consuming push budget

### Behavioral Constraints

- Cannot start in the background (unless push-to-start on iOS 17.2+)
- No ads, promotions, or marketing (Apple enforces in App Review)
- No standard SwiftUI buttons — only `Button(_:intent:)` via App Intents (iOS 17+)
- Widget Extension runs in a separate process — no access to main app state, networking, or databases
- Images must be local files (no network loading in Widget Extension)

---

## 2. FLUTTER IMPLEMENTATION FOR iOS

### Plugin: `live_activities` (pub.dev, v2.4.6)

```yaml
dependencies:
  live_activities: ^2.4.6
```

### Setup Steps

1. **Initialize in Flutter:**
```dart
final _liveActivities = LiveActivities();
await _liveActivities.init(
  appGroupId: 'group.com.yourcompany.airtime',
  urlScheme: 'airtime',
);
```

2. **Create Widget Extension in Xcode:**
   - Open `ios/Runner.xcworkspace`
   - File > New > Target > Widget Extension
   - Add App Group capability to both Runner and Widget Extension (same group ID)
   - Add `NSSupportsLiveActivities = YES` to Info.plist of both targets
   - Add Push Notifications capability to Runner

3. **Write Swift code** for `LiveActivitiesAppAttributes` (required exact name for plugin) and SwiftUI views

4. **Data flow:** Flutter writes key-value pairs to UserDefaults (App Group) → Widget Extension reads them and renders SwiftUI

### Flutter API

```dart
// Check support
final isSupported = await _liveActivities.areActivitiesEnabled();

// CREATE
final activityId = await _liveActivities.createActivity({
  'activityType': 'flight',
  'flightNumber': 'LX147',
  'departureAirport': 'DEL',
  'arrivalAirport': 'ZRH',
  'status': 'Scheduled',
  'departureGate': 'T3',
  'estimatedDeparture': '01:45',
}, iOSEnableRemoteUpdates: true);

// UPDATE
await _liveActivities.updateActivity(activityId: activityId, data: {
  'status': 'Boarding',
  'departureGate': 'B22',
});

// END
await _liveActivities.endActivity(activityId: activityId);

// GET push token for server-side updates
_liveActivities.activityUpdateStream.listen((event) {
  event.map(
    active: (active) => sendTokenToServer(active.activityToken),
    ended: (ended) => removeTokenFromServer(ended.activityId),
    unknown: (_) {},
  );
});

// DEEP LINK from Live Activity tap
_liveActivities.urlSchemeStream().listen((schemeData) {
  navigateToFlightDetails(schemeData.queryItems['flightId']);
});
```

### Multi-Purpose Design (Single Implementation, Many Use Cases)

Use a `activityType` discriminator field and conditionally render different SwiftUI views:

```swift
// In Widget Extension
struct MyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            let activityType = sharedDefaults.string(forKey: context.attributes.prefixedKey("activityType")) ?? "default"

            switch activityType {
            case "flight":
                FlightLockScreenView(context: context)
            case "train":
                TrainLockScreenView(context: context)
            case "delivery":
                DeliveryLockScreenView(context: context)
            default:
                DefaultLockScreenView(context: context)
            }
        } dynamicIsland: { context in
            // Same pattern — switch on activityType for each region
        }
    }
}
```

---

## 3. ANDROID: WHAT'S THE EQUIVALENT?

### The Spotify Construct: Foreground Service + MediaStyle Notification

What Spotify shows on the lock screen and notification shade is a **Foreground Service** paired with a **MediaStyle ongoing notification** via the **Media3 MediaSessionService**.

**How it works:**
- A `MediaSessionService` runs in the background with `foregroundServiceType="mediaPlayback"`
- It creates a `MediaSession` that publishes metadata (title, artist, album art) and playback state
- Media3 automatically generates a `MediaStyle` notification with play/pause/skip controls
- The notification is persistent (`setOngoing(true)`) — cannot be swiped away
- System automatically shows it on the lock screen media player widget
- Integrates with Google Assistant, Bluetooth controls, Wear OS, and Android Auto

### For Non-Media Use Cases (Flight Tracking, Ride Sharing, Deliveries)

Android uses **Foreground Service + ongoing notification**:

```kotlin
val notification = NotificationCompat.Builder(this, "tracking_channel")
    .setSmallIcon(R.drawable.ic_flight)
    .setContentTitle("LX147 — On Time")
    .setContentText("DEL → ZRH | Departs 01:45 AM | Gate T3")
    .setOngoing(true)                    // Cannot be dismissed
    .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // Show on lock screen
    .setStyle(NotificationCompat.BigTextStyle()
        .bigText("Gate: T3 | Terminal: 3\nDeparting: 01:45 AM (On Time)\nArriving: 06:20 AM\nAircraft: Airbus A330-300"))
    .addAction(R.drawable.ic_share, "Share", sharePendingIntent)
    .build()

startForeground(NOTIFICATION_ID, notification)
```

**Updating:** Call `NotificationManager.notify()` with the same ID to update content in-place.

### Android 14+ Foreground Service Types

Starting with Android 14, every foreground service must declare a specific type:

| Type | Use Case |
|------|----------|
| `mediaPlayback` | Audio/video playback (Spotify) |
| `location` | Navigation, ride/delivery tracking |
| `dataSync` | Upload/download, flight status polling |
| `connectedDevice` | Bluetooth/NFC |
| `shortService` | Quick critical work (~3 min) |

### Android 16 "Live Updates" — The Direct Answer to iOS Live Activities

**Android 16 (API 36)** introduces `Notification.ProgressStyle` — Google's direct equivalent to iOS Live Activities. Available in Android 16 QPR1 beta (expected wide rollout Q2 2026).

**What it adds:**
- **Status bar chips** showing real-time text/countdowns (like Dynamic Island compact view)
- **Top ranking** in the notification drawer (promoted ongoing notifications)
- **Prominent lock screen display**
- **Progress visualization** with Segments (colored phases) and Points (milestones)

**Requires:**
```xml
<uses-permission android:name="android.permission.POST_PROMOTED_NOTIFICATIONS" />
```

**Implementation:**
```kotlin
val enRouteSegment = Notification.ProgressStyle.Segment(100).setColor(Color.GREEN)
val remainingSegment = Notification.ProgressStyle.Segment(100).setColor(Color.GRAY)

val progressStyle = Notification.ProgressStyle()
    .setProgressSegments(listOf(enRouteSegment, remainingSegment))

val notification = Notification.Builder(context, channelId)
    .setContentTitle("LX147 — En Route")
    .setContentText("Arriving ZRH in 5h 35m")
    .setStyle(progressStyle)
    .setOngoing(true)
    .setRequestPromotedOngoing(true)       // Request promotion
    .setShortCriticalText("5h 35m")        // Status bar chip text (max 96dp)
    .setChronometerCountdown(true)          // Countdown mode
    .build()
```

**Restrictions — notification must NOT:**
- Have custom RemoteViews via `setCustomContentView()`
- Be a group summary
- Have `setColorized(true)`
- Use a channel with `IMPORTANCE_MIN`

### Available Notification Styles (Pre-Android 16)

| Style | Purpose |
|-------|---------|
| `BigTextStyle` | Expanded text view — good for flight details |
| `BigPictureStyle` | Large image — good for maps |
| `InboxStyle` | Multiple lines — good for multi-flight summaries |
| `MediaStyle` | Media controls — Spotify/music |
| `DecoratedCustomViewStyle` | Custom XML layout via RemoteViews — richest option |
| Progress bar | `setProgress(max, current, indeterminate)` |
| Chronometer | `setUsesChronometer(true)` — live elapsed/countdown time |

### Widgets (Home Screen)

Android home screen widgets can show real-time data but have limitations:
- `updatePeriodMillis` minimum is **30 minutes**
- For more frequent updates, use `WorkManager` (min 15-minute intervals) or trigger from a foreground service
- Jetpack Glance (Compose-based) is the modern approach
- **Not a replacement** for ongoing notifications for truly real-time scenarios

---

## 4. FLUTTER IMPLEMENTATION FOR ANDROID

### Option A: `flutter_local_notifications` (Ongoing Notification)

Already in Airtime's dependencies.

```dart
const androidDetails = AndroidNotificationDetails(
  'flight_tracking',
  'Flight Tracking',
  channelDescription: 'Live flight tracking updates',
  importance: Importance.low,       // No sound
  priority: Priority.low,
  ongoing: true,                    // Cannot be dismissed
  autoCancel: false,
  showWhen: true,
  usesChronometer: true,            // Live elapsed time
  category: AndroidNotificationCategory.transport,
  visibility: NotificationVisibility.public,  // Show on lock screen
  styleInformation: BigTextStyleInformation(
    'Gate: T3 | Terminal: 3\nDeparting: 01:45 AM (On Time)\nArriving: 06:20 AM\nAircraft: Airbus A330-300',
    contentTitle: 'LX147 — On Time',
    summaryText: 'DEL → ZRH',
  ),
);

await flutterLocalNotificationsPlugin.show(
  0, 'LX147 — On Time', 'DEL → ZRH | Departs 01:45 AM',
  const NotificationDetails(android: androidDetails),
);
```

### Option B: `flutter_foreground_task` (Foreground Service + Periodic Updates)

```yaml
dependencies:
  flutter_foreground_task: ^8.0.0
```

```dart
await FlutterForegroundTask.startService(
  serviceId: 256,
  notificationTitle: 'LX147 — On Time',
  notificationText: 'DEL → ZRH | Departs 01:45 AM',
  callback: startCallback,
);

class FlightTrackingHandler extends TaskHandler {
  @override
  void onRepeatEvent(DateTime timestamp) {
    // Fetch latest flight status from Cirium
    // Update notification:
    FlutterForegroundTask.updateService(
      notificationTitle: 'LX147 — Boarding',
      notificationText: 'Gate B22 | Departs 01:45 AM',
    );
  }
}
```

### Option C: `live_activities` Plugin (Cross-Platform, Android in Beta)

The same `live_activities` plugin used for iOS has experimental Android support via custom RemoteViews. Requires:
1. Custom XML layout at `android/app/src/main/res/layout/live_activity.xml`
2. Kotlin `CustomLiveActivityManager` extending the plugin's manager

---

## 5. COMPARISON: iOS vs ANDROID

| Aspect | iOS Live Activities | Android (Today) | Android 16+ Live Updates |
|--------|-------------------|-----------------|--------------------------|
| **Lock screen** | Dedicated area at bottom | Standard notification card | Promoted, top-ranked card |
| **Dynamic Island / Status bar** | Dynamic Island (3 modes) | Nothing | Status bar chip with countdown |
| **Custom UI** | Full SwiftUI | RemoteViews (XML) | Templated ProgressStyle |
| **Rich progress** | Custom SwiftUI views | Basic progress bar | Segments + Points |
| **Duration** | Max 12 hours then auto-dismissed | Unlimited while service runs | Unlimited |
| **Remote updates** | Own APNs push token per activity | FCM silent push | FCM silent push |
| **Update frequency** | 5-15 second render intervals | Immediate | Immediate |
| **Stale handling** | Auto-transitions to stale state | Stays forever | Stays forever |
| **Interactivity** | Tap to deep link, App Intent buttons | Action buttons, tap to open | Action buttons, tap to open |
| **Always-On Display** | Consistent across all iPhones | Varies by OEM | Varies by OEM |
| **Framework** | ActivityKit + WidgetKit | NotificationCompat + Service | Notification.ProgressStyle |
| **Flutter plugin** | `live_activities` (mature) | `flutter_foreground_task` / `flutter_local_notifications` | Not yet available |
| **Min OS** | iOS 16.1 | Any | Android 16 (API 36) |

### What Android Has That iOS Doesn't
- **Unlimited duration** — iOS auto-expires after 12 hours
- **More action buttons** — up to 5 (3 in compact view)
- **Custom notification layouts** — `DecoratedCustomViewStyle` with RemoteViews
- **Foreground service guarantees** — keeps process alive more reliably

### What iOS Has That Android Doesn't (Yet)
- **Dynamic Island** — no true Android equivalent; status bar chips are simpler
- **Dedicated lock screen area** — iOS Live Activities get their own visual space
- **Full SwiftUI rendering** — much richer UI than Android's RemoteViews or ProgressStyle templates
- **Per-activity push tokens** — dedicated push mechanism; Android reuses FCM
- **Graceful stale/dismissal** — iOS auto-transitions and auto-dismisses; Android notifications just stay

---

## 6. STRATEGY FOR AIRTIME

### iOS Implementation Plan
1. Add `live_activities` plugin to pubspec.yaml
2. Create Widget Extension in Xcode with App Group
3. Define `LiveActivitiesAppAttributes` with `activityType` discriminator
4. Build SwiftUI views for flight tracking (Lock Screen + Dynamic Island)
5. Start Live Activity when user adds a flight or views flight details
6. Backend (Cirium alert webhook) sends APNs push updates to the activity's push token
7. End activity when flight lands or user dismisses
8. Later: extend with train tracking, delivery views using same `activityType` switch

### Android Implementation Plan
1. **Today:** Use `flutter_foreground_task` for a foreground service with ongoing `BigTextStyle` notification
2. Update notification content when Cirium FCM pushes arrive (gate changes, delays, status updates)
3. **When Android 16 is stable (mid-2026):** Migrate to `Notification.ProgressStyle` with promoted ongoing for status bar chip + segments

### Shared Backend Changes Needed
- Store Live Activity push tokens alongside FCM tokens in Firestore
- Cirium alert webhook sends both FCM (Android) and APNs Live Activity push (iOS)
- Push-to-start token support for automatically starting Live Activities from webhook without app being open (iOS 17.2+)

---

*Last updated: 2026-02-07*
*Sources: Apple Developer Documentation, Android Developer Documentation, WWDC23/24, Google I/O 2025, pub.dev, Grab Engineering Blog*
