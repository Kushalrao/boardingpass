import 'package:cloud_firestore/cloud_firestore.dart';

class Account {
  final String id;
  final String type; // 'bank_account', 'credit_card', 'upi', 'wallet'
  final String provider;
  final String maskedNumber;
  final String? nickname;
  final int transactionCount;

  Account({
    required this.id,
    required this.type,
    required this.provider,
    required this.maskedNumber,
    this.nickname,
    this.transactionCount = 0,
  });

  factory Account.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Account(
      id: doc.id,
      type: data['type'] as String? ?? 'bank_account',
      provider: data['provider'] as String? ?? 'Unknown',
      maskedNumber: data['maskedNumber'] as String? ?? '****',
      nickname: data['nickname'] as String?,
      transactionCount: (data['transactionCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'provider': provider,
      'maskedNumber': maskedNumber,
      'nickname': nickname,
      'transactionCount': transactionCount,
    };
  }

  String get displayName => nickname ?? '$provider $maskedNumber';

  String get typeLabel {
    switch (type) {
      case 'bank_account':
        return 'Bank Account';
      case 'credit_card':
        return 'Credit Card';
      case 'upi':
        return 'UPI';
      case 'wallet':
        return 'Wallet';
      default:
        return type;
    }
  }

  Account copyWith({
    String? id,
    String? type,
    String? provider,
    String? maskedNumber,
    String? nickname,
    int? transactionCount,
  }) {
    return Account(
      id: id ?? this.id,
      type: type ?? this.type,
      provider: provider ?? this.provider,
      maskedNumber: maskedNumber ?? this.maskedNumber,
      nickname: nickname ?? this.nickname,
      transactionCount: transactionCount ?? this.transactionCount,
    );
  }
}
