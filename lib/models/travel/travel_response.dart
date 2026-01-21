import 'bookings.dart';
import 'booking_types.dart';

class TravelAnalysisResponse {
  final List<Booking> travels;
  final bool moreBatches;
  final int? nextBatch;
  final int? totalEmails;

  TravelAnalysisResponse({
    required this.travels,
    required this.moreBatches,
    this.nextBatch,
    this.totalEmails,
  });

  factory TravelAnalysisResponse.fromJson(Map<String, dynamic> json) {
    return TravelAnalysisResponse(
      travels: (json['travels'] as List<dynamic>?)
              ?.map((e) => Booking.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      moreBatches: json['moreBatches'] as bool? ?? false,
      nextBatch: json['nextBatch'] as int?,
      totalEmails: json['totalEmails'] as int?,
    );
  }

  double get totalSpentINR {
    return travels
        .where((t) => t.amountINR != null)
        .fold(0.0, (sum, t) => sum + (t.amountINR ?? 0));
  }

  int get flightCount =>
      travels.where((t) => t.bookingType == BookingType.flight).length;

  int get hotelCount =>
      travels.where((t) => t.bookingType == BookingType.hotel).length;

  int get trainCount =>
      travels.where((t) => t.bookingType == BookingType.train).length;

  int get busCount =>
      travels.where((t) => t.bookingType == BookingType.bus).length;
}
