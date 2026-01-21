import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/travel/travel_response.dart';
import '../models/travel/bookings.dart';
import 'auth_service.dart';

class TravelService {
  final AuthService _authService;
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  TravelService({
    required AuthService authService,
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _authService = authService,
        _functions = functions ?? FirebaseFunctions.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Analyze travel from Gmail and store results
  Future<TravelAnalysisResponse> analyzeTravel({
    int batchSize = 5,
    int batch = 1,
    int? year,
    bool saveToFirestore = true,
  }) async {
    // Check if user is signed in
    if (!_authService.isSignedIn) {
      throw Exception('Not signed in. Please sign in first.');
    }

    // Get Gmail access token
    final accessToken = await _authService.getGmailAccessToken();
    if (accessToken == null) {
      throw Exception('Could not get Gmail access. Please sign in again.');
    }

    // Call Firebase Function
    final callable = _functions.httpsCallable(
      'analyzeTravel',
      options: HttpsCallableOptions(
        timeout: const Duration(minutes: 9),
      ),
    );

    try {
      debugPrint('[TravelService] Calling analyzeTravel function...');
      final result = await callable.call<Map<String, dynamic>>({
        'accessToken': accessToken,
        'options': {
          'batchSize': batchSize,
          'batch': batch,
          if (year != null) 'year': year,
        },
      });

      final response = TravelAnalysisResponse.fromJson(result.data);
      debugPrint('[TravelService] Got ${response.travels.length} travel records');

      // Save to Firestore if requested
      if (saveToFirestore && response.travels.isNotEmpty) {
        await _saveTravelsToFirestore(response.travels);
      }

      return response;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[TravelService] Firebase Functions error: ${e.code} - ${e.message}');
      throw Exception('Failed to analyze travel: ${e.message}');
    } catch (e) {
      debugPrint('[TravelService] Error calling analyzeTravel: $e');
      throw Exception('Failed to analyze travel: $e');
    }
  }

  /// Analyze all travel batches
  Future<List<TravelAnalysisResponse>> analyzeAllTravel({
    int batchSize = 5,
    int? year,
    bool saveToFirestore = true,
    void Function(int current, int? total)? onProgress,
  }) async {
    final responses = <TravelAnalysisResponse>[];
    int batch = 1;
    bool hasMore = true;

    while (hasMore) {
      final response = await analyzeTravel(
        batchSize: batchSize,
        batch: batch,
        year: year,
        saveToFirestore: saveToFirestore,
      );

      responses.add(response);
      onProgress?.call(batch, null);

      hasMore = response.moreBatches;
      batch = response.nextBatch ?? batch + 1;
    }

    return responses;
  }

  /// Save travel records to Firestore under user's collection
  Future<void> _saveTravelsToFirestore(List<Booking> travels) async {
    final userId = _authService.userId;
    if (userId == null) return;

    debugPrint('[TravelService] Saving ${travels.length} travels to Firestore...');

    final batch = _firestore.batch();
    final travelsCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('travels');

    for (final travel in travels) {
      // Use email message ID as document ID to avoid duplicates
      final docId = travel.emailMessageId ?? travel.confirmationNumber ?? DateTime.now().millisecondsSinceEpoch.toString();
      final docRef = travelsCollection.doc(docId);

      batch.set(docRef, {
        ...travel.toJson(),
        'savedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    debugPrint('[TravelService] Saved travels to Firestore');
  }

  /// Get user's saved travels from Firestore
  Future<List<Booking>> getSavedTravels({
    int? limit,
    String? bookingType,
  }) async {
    final userId = _authService.userId;
    if (userId == null) {
      throw Exception('Not signed in');
    }

    Query query = _firestore
        .collection('users')
        .doc(userId)
        .collection('travels')
        .orderBy('savedAt', descending: true);

    if (bookingType != null) {
      query = query.where('booking_type', isEqualTo: bookingType);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => Booking.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Get travel statistics for user
  Future<Map<String, dynamic>> getTravelStats() async {
    final userId = _authService.userId;
    if (userId == null) {
      throw Exception('Not signed in');
    }

    final travelsCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('travels');

    final snapshot = await travelsCollection.get();
    final travels = snapshot.docs
        .map((doc) => Booking.fromJson(doc.data()))
        .toList();

    // Calculate stats
    int flightCount = 0;
    int hotelCount = 0;
    int trainCount = 0;
    int busCount = 0;
    double totalSpent = 0;

    for (final travel in travels) {
      switch (travel.bookingType.name) {
        case 'flight':
          flightCount++;
          break;
        case 'hotel':
          hotelCount++;
          break;
        case 'train':
          trainCount++;
          break;
        case 'bus':
          busCount++;
          break;
      }

      if (travel.amountINR != null) {
        totalSpent += travel.amountINR!;
      }
    }

    return {
      'totalTrips': travels.length,
      'flightCount': flightCount,
      'hotelCount': hotelCount,
      'trainCount': trainCount,
      'busCount': busCount,
      'totalSpentINR': totalSpent,
    };
  }

  /// Delete a saved travel record
  Future<void> deleteTravel(String travelId) async {
    final userId = _authService.userId;
    if (userId == null) {
      throw Exception('Not signed in');
    }

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('travels')
        .doc(travelId)
        .delete();
  }
}
