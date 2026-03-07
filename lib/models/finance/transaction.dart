import 'package:cloud_firestore/cloud_firestore.dart';

class Transaction {
  final String id;
  final String accountId;
  final String type; // 'debit' or 'credit'
  final double amount;
  final String currency;
  final double amountINR;
  final String merchant;
  final String merchantRaw;
  final String category;
  final String? subcategory;
  final DateTime date;
  final DateTime emailDate;
  final String emailMessageId;
  final String source;
  final String emailType;
  final String status;
  final bool statementConfirmed;
  final List<String> tags;
  final String? notes;
  final String? referenceNumber;

  Transaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.amountINR,
    required this.merchant,
    required this.merchantRaw,
    required this.category,
    this.subcategory,
    required this.date,
    required this.emailDate,
    required this.emailMessageId,
    required this.source,
    required this.emailType,
    required this.status,
    this.statementConfirmed = false,
    this.tags = const [],
    this.notes,
    this.referenceNumber,
  });

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Transaction(
      id: doc.id,
      accountId: data['accountId'] as String? ?? '',
      type: data['type'] as String? ?? 'debit',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] as String? ?? 'INR',
      amountINR: (data['amountINR'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble() ?? 0.0,
      merchant: data['merchant'] as String? ?? 'Unknown',
      merchantRaw: data['merchantRaw'] as String? ?? data['merchant'] as String? ?? '',
      category: data['category'] as String? ?? 'Uncategorized',
      subcategory: data['subcategory'] as String?,
      date: data['date'] is Timestamp
          ? (data['date'] as Timestamp).toDate()
          : DateTime.tryParse(data['date']?.toString() ?? '') ?? DateTime.now(),
      emailDate: data['emailDate'] is Timestamp
          ? (data['emailDate'] as Timestamp).toDate()
          : DateTime.tryParse(data['emailDate']?.toString() ?? '') ?? DateTime.now(),
      emailMessageId: data['emailMessageId'] as String? ?? '',
      source: data['source'] as String? ?? '',
      emailType: data['emailType'] as String? ?? '',
      status: data['status'] as String? ?? 'processed',
      statementConfirmed: data['statementConfirmed'] as bool? ?? false,
      tags: (data['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      notes: data['notes'] as String?,
      referenceNumber: data['referenceNumber'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'accountId': accountId,
      'type': type,
      'amount': amount,
      'currency': currency,
      'amountINR': amountINR,
      'merchant': merchant,
      'merchantRaw': merchantRaw,
      'category': category,
      'subcategory': subcategory,
      'date': Timestamp.fromDate(date),
      'emailDate': Timestamp.fromDate(emailDate),
      'emailMessageId': emailMessageId,
      'source': source,
      'emailType': emailType,
      'status': status,
      'statementConfirmed': statementConfirmed,
      'tags': tags,
      'notes': notes,
      'referenceNumber': referenceNumber,
    };
  }

  bool get isDebit => type == 'debit';
  bool get isCredit => type == 'credit';

  Transaction copyWith({
    String? id,
    String? accountId,
    String? type,
    double? amount,
    String? currency,
    double? amountINR,
    String? merchant,
    String? merchantRaw,
    String? category,
    String? subcategory,
    DateTime? date,
    DateTime? emailDate,
    String? emailMessageId,
    String? source,
    String? emailType,
    String? status,
    bool? statementConfirmed,
    List<String>? tags,
    String? notes,
    String? referenceNumber,
  }) {
    return Transaction(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      amountINR: amountINR ?? this.amountINR,
      merchant: merchant ?? this.merchant,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      date: date ?? this.date,
      emailDate: emailDate ?? this.emailDate,
      emailMessageId: emailMessageId ?? this.emailMessageId,
      source: source ?? this.source,
      emailType: emailType ?? this.emailType,
      status: status ?? this.status,
      statementConfirmed: statementConfirmed ?? this.statementConfirmed,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      referenceNumber: referenceNumber ?? this.referenceNumber,
    );
  }
}
