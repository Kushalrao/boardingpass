import * as functions from 'firebase-functions';
import { ApnsService } from '../services/apnsService';

const apnsService = new ApnsService();

/**
 * Firestore trigger: watches flight documents for alert updates.
 * When the existing ciriumAlertWebhook updates lastAlertType/lastAlertDetails,
 * this trigger sends an APNs push to the Live Activity (if a push token exists).
 *
 * This is a completely separate function — it does NOT modify any existing code.
 */
export const onFlightAlertUpdated = functions
  .runWith({ memory: '256MB' })
  .firestore.document('users/{userId}/flights/{flightId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Only proceed if lastAlertType or lastAlertDetails changed
    const alertTypeChanged = before.lastAlertType !== after.lastAlertType;
    const alertDetailsChanged =
      JSON.stringify(before.lastAlertDetails) !== JSON.stringify(after.lastAlertDetails);

    if (!alertTypeChanged && !alertDetailsChanged) {
      return;
    }

    // Check if there's a Live Activity push token
    const pushToken = after.liveActivityPushToken;
    if (!pushToken) {
      return; // No Live Activity running for this flight
    }

    if (!apnsService.isConfigured()) {
      console.log('[LiveActivity] APNs not configured — skipping push');
      return;
    }

    const eventType = after.lastAlertType as string;
    const details = after.lastAlertDetails || {};

    console.log(
      `[LiveActivity] Alert update: ${eventType} for flight ${after.fullFlightNumber || after.carrierFsCode + after.flightNumber}`
    );

    // Build ContentState from the flight document + alert details
    const contentState = buildContentState(after, eventType, details);

    // Send APNs push
    if (eventType === 'ARRIVAL') {
      // Send update first, then end
      await apnsService.sendLiveActivityUpdate(pushToken, contentState);
      // Small delay to ensure update renders before end
      await new Promise((resolve) => setTimeout(resolve, 2000));
      await apnsService.sendLiveActivityEnd(pushToken, contentState);
      console.log(`[LiveActivity] Sent update + end for landed flight`);
    } else {
      await apnsService.sendLiveActivityUpdate(pushToken, contentState);
      console.log(`[LiveActivity] Sent update for ${eventType}`);
    }
  });

/**
 * Build Live Activity ContentState from flight doc data and alert event.
 */
function buildContentState(
  flightData: FirebaseFirestore.DocumentData,
  eventType: string,
  details: Record<string, any>
) {
  // Determine status string
  let status = 'Scheduled';
  let progress = 0;

  switch (eventType) {
    case 'DEPARTURE':
      status = 'In Flight';
      progress = 10; // Just departed
      break;
    case 'ARRIVAL':
      status = 'Landed';
      progress = 100;
      break;
    case 'CANCELLATION':
      status = 'Cancelled';
      progress = 0;
      break;
    case 'DIVERSION':
      status = 'Diverted';
      progress = 50;
      break;
    case 'DELAY':
    case 'DEPARTURE_DELAY':
      // Keep current status, just update delay
      status = flightData.flightStatus?.status === 'A' ? 'In Flight' : 'Delayed';
      break;
    case 'GATE_CHANGE':
    case 'GATE_DEPARTURE':
      status = flightData.flightStatus?.status === 'A' ? 'In Flight' : 'Scheduled';
      break;
    case 'BAGGAGE':
      status = 'Landed';
      progress = 100;
      break;
    default:
      status = 'Scheduled';
  }

  // Compute progress for in-flight
  if (status === 'In Flight' && flightData.departureTime && flightData.arrivalTime) {
    const now = Date.now();
    const depTime = new Date(flightData.departureTime).getTime();
    const arrTime = new Date(flightData.arrivalTime).getTime();
    const totalDuration = arrTime - depTime;
    const elapsed = now - depTime;
    if (totalDuration > 0) {
      progress = Math.min(100, Math.max(0, Math.round((elapsed / totalDuration) * 100)));
    }
  }

  // Parse times — use flightStatus estimated times if available, fall back to scheduled
  const flightStatus = flightData.flightStatus || {};
  const estimatedDeparture = parseTimeToUnix(
    flightStatus.estimatedDeparture || flightStatus.scheduledDeparture || flightData.departureTime
  );
  const estimatedArrival = parseTimeToUnix(
    flightStatus.estimatedArrival || flightStatus.scheduledArrival || flightData.arrivalTime
  );

  // Delay minutes
  const delayMinutes = details.delayMinutes
    ? parseInt(details.delayMinutes, 10)
    : (flightStatus.departureDelayMinutes || 0);

  return {
    status,
    departureGate: details.newGate || details.gate || flightStatus.departureGate || null,
    arrivalGate: flightStatus.arrivalGate || null,
    departureTerminal: flightStatus.departureTerminal || flightData.departureTerminal || null,
    arrivalTerminal: flightStatus.arrivalTerminal || flightData.arrivalTerminal || null,
    estimatedDeparture,
    estimatedArrival,
    delayMinutes,
    progress,
    baggageBelt: details.baggageBelt || details.baggage || flightStatus.baggageBelt || null,
    diversionAirport: details.diversionAirport || null,
  };
}

/**
 * Parse an ISO date string or timestamp to Unix seconds.
 */
function parseTimeToUnix(time: any): number {
  if (!time) return Math.floor(Date.now() / 1000);
  if (typeof time === 'number') return time;
  const parsed = new Date(time).getTime();
  return isNaN(parsed) ? Math.floor(Date.now() / 1000) : Math.floor(parsed / 1000);
}
