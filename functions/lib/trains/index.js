"use strict";
/**
 * Train Functions for Indian Railways
 *
 * This module provides Firebase callable functions for:
 * - PNR status checking
 * - Train schedule lookup
 * - Live running status
 * - Train search
 * - User train bookings management
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onTrainCreated = exports.deleteTrainBooking = exports.refreshTrainStatus = exports.getUserTrains = exports.addTrainBooking = exports.searchTrains = exports.getTrainLiveStatus = exports.getTrainSchedule = exports.getTrainPnrStatus = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const trainScraperService_1 = require("./services/trainScraperService");
// Ensure Firebase Admin is initialized
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
/**
 * Get PNR Status
 * Public function - no authentication required
 */
exports.getTrainPnrStatus = functions
    .runWith({
    timeoutSeconds: 120,
    memory: '512MB',
})
    .https.onCall(async (data) => {
    const { pnr } = data;
    if (!pnr || !/^\d{10}$/.test(pnr)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid PNR. Must be 10 digits.');
    }
    console.log(`Fetching PNR status for: ${pnr}`);
    const scraperService = (0, trainScraperService_1.getTrainScraperService)();
    const result = await scraperService.getPnrStatus(pnr);
    if (!result.success) {
        console.error(`PNR fetch failed: ${result.error}`);
    }
    return result;
});
/**
 * Get Train Schedule
 * Public function - no authentication required
 */
exports.getTrainSchedule = functions
    .runWith({
    timeoutSeconds: 120,
    memory: '512MB',
})
    .https.onCall(async (data) => {
    const { trainNumber } = data;
    if (!trainNumber || !/^\d{5}$/.test(trainNumber)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid train number. Must be 5 digits.');
    }
    console.log(`Fetching schedule for train: ${trainNumber}`);
    const scraperService = (0, trainScraperService_1.getTrainScraperService)();
    const result = await scraperService.getTrainSchedule(trainNumber);
    if (!result.success) {
        console.error(`Schedule fetch failed: ${result.error}`);
    }
    return result;
});
/**
 * Get Train Live Status
 * Public function - no authentication required
 */
exports.getTrainLiveStatus = functions
    .runWith({
    timeoutSeconds: 120,
    memory: '512MB',
})
    .https.onCall(async (data) => {
    const { trainNumber, date } = data;
    if (!trainNumber || !/^\d{5}$/.test(trainNumber)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid train number. Must be 5 digits.');
    }
    // Validate date format if provided (YYYYMMDD)
    if (date && !/^\d{8}$/.test(date)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid date format. Must be YYYYMMDD.');
    }
    console.log(`Fetching live status for train: ${trainNumber}, date: ${date || 'today'}`);
    const scraperService = (0, trainScraperService_1.getTrainScraperService)();
    const result = await scraperService.getLiveStatus(trainNumber, date);
    if (!result.success) {
        console.error(`Live status fetch failed: ${result.error}`);
    }
    return result;
});
/**
 * Search Trains
 * Public function - no authentication required
 */
exports.searchTrains = functions
    .runWith({
    timeoutSeconds: 60,
    memory: '256MB',
})
    .https.onCall(async (data) => {
    const { from, to, date } = data;
    if (!from || !to) {
        throw new functions.https.HttpsError('invalid-argument', 'Both from and to station codes are required.');
    }
    // Station codes are typically 2-5 uppercase letters
    const stationCodeRegex = /^[A-Z]{2,5}$/;
    const fromCode = from.toUpperCase();
    const toCode = to.toUpperCase();
    if (!stationCodeRegex.test(fromCode) || !stationCodeRegex.test(toCode)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid station code format.');
    }
    console.log(`Searching trains from ${fromCode} to ${toCode}`);
    const scraperService = (0, trainScraperService_1.getTrainScraperService)();
    const result = await scraperService.searchTrains(fromCode, toCode, date);
    if (!result.success) {
        console.error(`Train search failed: ${result.error}`);
    }
    return result;
});
/**
 * Add Train Booking
 * Requires authentication - stores train in user's collection
 */
exports.addTrainBooking = functions
    .runWith({
    timeoutSeconds: 120,
    memory: '512MB',
})
    .https.onCall(async (data, context) => {
    // Require authentication
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const userId = context.auth.uid;
    const { pnr, trainNumber, journeyDate, fromStation, toStation } = data;
    // Validate: either PNR or (trainNumber + stations) required
    if (!pnr && !trainNumber) {
        throw new functions.https.HttpsError('invalid-argument', 'Either PNR or train number is required.');
    }
    if (!journeyDate) {
        throw new functions.https.HttpsError('invalid-argument', 'Journey date is required.');
    }
    console.log(`Adding train booking for user ${userId}: PNR=${pnr}, Train=${trainNumber}`);
    const scraperService = (0, trainScraperService_1.getTrainScraperService)();
    let trainBooking;
    if (pnr) {
        // Fetch PNR status and create booking from it
        const pnrStatus = await scraperService.getPnrStatus(pnr);
        if (!pnrStatus.success) {
            throw new functions.https.HttpsError('not-found', pnrStatus.error || 'Could not fetch PNR status');
        }
        trainBooking = {
            pnr,
            trainNumber: pnrStatus.trainNumber || '',
            trainName: pnrStatus.trainName,
            journeyDate: pnrStatus.journeyDate || journeyDate,
            fromStation: pnrStatus.fromStation || { code: '', name: '' },
            toStation: pnrStatus.toStation || { code: '', name: '' },
            travelClass: pnrStatus.travelClass,
            quota: pnrStatus.quota,
            passengers: pnrStatus.passengers,
            chartStatus: pnrStatus.chartStatus,
            overallStatus: pnrStatus.overallStatus,
            confirmationChance: pnrStatus.confirmationChance,
            source: 'manual',
            savedAt: new Date().toISOString(),
            lastChecked: new Date().toISOString(),
        };
    }
    else {
        // Create booking from train number (for live tracking)
        if (!fromStation || !toStation) {
            throw new functions.https.HttpsError('invalid-argument', 'From and to stations are required when not using PNR.');
        }
        // Optionally fetch schedule to get train name
        let trainName;
        try {
            const schedule = await scraperService.getTrainSchedule(trainNumber);
            if (schedule.success) {
                trainName = schedule.trainName;
            }
        }
        catch (e) {
            console.log('Could not fetch train name, continuing without it');
        }
        trainBooking = {
            trainNumber: trainNumber,
            trainName,
            journeyDate,
            fromStation: { code: fromStation.toUpperCase(), name: fromStation },
            toStation: { code: toStation.toUpperCase(), name: toStation },
            passengers: [],
            source: 'query',
            savedAt: new Date().toISOString(),
        };
    }
    // Save to Firestore
    const docRef = await db
        .collection('users')
        .doc(userId)
        .collection('trains')
        .add({
        ...trainBooking,
        savedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastChecked: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`Saved train booking ${docRef.id} for user ${userId}`);
    return {
        success: true,
        trainId: docRef.id,
        data: { ...trainBooking, id: docRef.id },
    };
});
/**
 * Get User's Train Bookings
 * Requires authentication
 */
exports.getUserTrains = functions
    .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
})
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const userId = context.auth.uid;
    const { upcoming, limit } = data;
    console.log(`Fetching trains for user ${userId}, upcoming=${upcoming}, limit=${limit}`);
    let query = db
        .collection('users')
        .doc(userId)
        .collection('trains')
        .orderBy('journeyDate', 'desc');
    if (upcoming) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        query = query.where('journeyDate', '>=', today.toISOString());
    }
    if (limit) {
        query = query.limit(limit);
    }
    const snapshot = await query.get();
    const trains = [];
    snapshot.forEach((doc) => {
        const data = doc.data();
        trains.push({
            id: doc.id,
            ...data,
            journeyDate: data.journeyDate?.toDate?.()?.toISOString() || data.journeyDate,
            savedAt: data.savedAt?.toDate?.()?.toISOString() || data.savedAt,
            lastChecked: data.lastChecked?.toDate?.()?.toISOString() || data.lastChecked,
        });
    });
    console.log(`Found ${trains.length} trains for user ${userId}`);
    return { trains };
});
/**
 * Refresh Train Status
 * Updates PNR status for a saved train booking
 * Requires authentication
 */
exports.refreshTrainStatus = functions
    .runWith({
    timeoutSeconds: 120,
    memory: '512MB',
})
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const userId = context.auth.uid;
    const { trainId } = data;
    if (!trainId) {
        throw new functions.https.HttpsError('invalid-argument', 'Train ID is required');
    }
    console.log(`Refreshing train ${trainId} for user ${userId}`);
    // Get existing train document
    const trainRef = db
        .collection('users')
        .doc(userId)
        .collection('trains')
        .doc(trainId);
    const trainDoc = await trainRef.get();
    if (!trainDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Train booking not found');
    }
    const trainData = trainDoc.data();
    const scraperService = (0, trainScraperService_1.getTrainScraperService)();
    // If has PNR, refresh PNR status
    if (trainData.pnr) {
        const pnrStatus = await scraperService.getPnrStatus(trainData.pnr);
        if (pnrStatus.success) {
            const updates = {
                passengers: pnrStatus.passengers,
                chartStatus: pnrStatus.chartStatus,
                overallStatus: pnrStatus.overallStatus,
                confirmationChance: pnrStatus.confirmationChance,
                lastChecked: new Date().toISOString(),
            };
            await trainRef.update({
                ...updates,
                lastChecked: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`Updated PNR status for train ${trainId}`);
            return {
                success: true,
                data: { ...trainData, ...updates, id: trainId },
            };
        }
    }
    // If no PNR or PNR fetch failed, try to get live status
    if (trainData.trainNumber) {
        const liveStatus = await scraperService.getLiveStatus(trainData.trainNumber);
        if (liveStatus.success) {
            const updates = {
                liveStatus: {
                    currentStation: liveStatus.currentStation,
                    delay: liveStatus.delay,
                    lastUpdated: liveStatus.lastUpdated,
                },
                lastChecked: new Date().toISOString(),
            };
            await trainRef.update({
                ...updates,
                lastChecked: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`Updated live status for train ${trainId}`);
            return {
                success: true,
                data: { ...trainData, ...updates, id: trainId },
            };
        }
    }
    // Just update lastChecked if nothing else worked
    await trainRef.update({
        lastChecked: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
        success: true,
        data: { ...trainData, id: trainId, lastChecked: new Date().toISOString() },
    };
});
/**
 * Delete Train Booking
 * Requires authentication
 */
exports.deleteTrainBooking = functions
    .runWith({
    timeoutSeconds: 30,
    memory: '256MB',
})
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const userId = context.auth.uid;
    const { trainId } = data;
    if (!trainId) {
        throw new functions.https.HttpsError('invalid-argument', 'Train ID is required');
    }
    console.log(`Deleting train ${trainId} for user ${userId}`);
    await db
        .collection('users')
        .doc(userId)
        .collection('trains')
        .doc(trainId)
        .delete();
    return { success: true };
});
/**
 * Firestore trigger: When a train is added, send notification
 */
exports.onTrainCreated = functions.firestore
    .document('users/{userId}/trains/{trainId}')
    .onCreate(async (snapshot, context) => {
    const { userId } = context.params;
    const trainData = snapshot.data();
    console.log(`Train added for user ${userId}: ${trainData.trainNumber} - ${trainData.trainName}`);
    // You can add FCM notification here similar to flights
    // For now, just log it
    console.log(`Train ${trainData.trainNumber} from ${trainData.fromStation?.name} to ${trainData.toStation?.name}`);
});
//# sourceMappingURL=index.js.map