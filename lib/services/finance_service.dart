import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import '../models/finance/transaction.dart' as finance;
import '../models/finance/account.dart';
import '../models/finance/aggregate.dart';

class FinanceService {
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final AuthService _authService;

  FinanceService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    AuthService? authService,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _authService = authService ?? AuthService();

  /// Get current user ID or throw
  String get _userId {
    final uid = _authService.userId;
    if (uid == null) throw Exception('User not signed in');
    return uid;
  }

  /// Reference to the user's finance subcollections
  DocumentReference get _userDoc => _firestore.collection('users').doc(_userId);

  /// Trigger batch analysis of financial emails
  Future<Map<String, dynamic>> analyzeFinance({
    int batch = 1,
    int batchSize = 10,
    String? afterDate,
  }) async {
    // Force refresh Firebase ID token to ensure callable auth works
    await FirebaseAuth.instance.currentUser?.getIdToken(true);

    final accessToken = await _authService.getGmailAccessToken();
    if (accessToken == null) throw Exception('No Gmail access token');

    debugPrint('[FinanceService] Analyzing finance emails (batch: $batch, batchSize: $batchSize, afterDate: $afterDate)...');

    final result = await _functions
        .httpsCallable(
          'analyzeFinance',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call({
      'accessToken': accessToken,
      'userId': _userId,
      'options': {
        'batch': batch,
        'batchSize': batchSize,
        if (afterDate != null) 'afterDate': afterDate,
      },
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    debugPrint('[FinanceService] Batch $batch complete: ${data['processedCount']} processed');
    return data;
  }

  /// Compute the afterDate string for 6-month lookback
  String _sixMonthsAgoDate() {
    final now = DateTime.now();
    final sixMonthsAgo = DateTime(now.year, now.month - 6, now.day);
    return '${sixMonthsAgo.year}/${sixMonthsAgo.month.toString().padLeft(2, '0')}/${sixMonthsAgo.day.toString().padLeft(2, '0')}';
  }

  /// Analyze all financial emails in batches, reporting progress
  Future<Map<String, dynamic>> analyzeAllFinance({
    int batchSize = 10,
    String? afterDate,
    Function(int processedSoFar, int totalEstimate)? onProgress,
  }) async {
    final effectiveAfterDate = afterDate ?? _sixMonthsAgoDate();
    int currentBatch = 1;
    int totalProcessed = 0;
    int totalEstimate = 0;
    bool moreBatches = true;

    while (moreBatches) {
      final result = await analyzeFinance(
        batch: currentBatch,
        batchSize: batchSize,
        afterDate: effectiveAfterDate,
      );

      final processedCount = (result['processedCount'] as num?)?.toInt() ?? 0;
      totalProcessed += processedCount;
      totalEstimate = (result['totalEmails'] as num?)?.toInt() ?? totalProcessed;
      moreBatches = result['moreBatches'] as bool? ?? false;

      onProgress?.call(totalProcessed, totalEstimate);

      if (moreBatches) {
        currentBatch++;
      }
    }

    debugPrint('[FinanceService] All batches complete. Total processed: $totalProcessed');

    return {
      'totalProcessed': totalProcessed,
      'totalBatches': currentBatch,
    };
  }

  /// Get user's detected accounts from Firestore
  Future<List<Account>> getAccounts() async {
    try {
      final snapshot = await _userDoc
          .collection('accounts')
          .orderBy('provider')
          .get();

      final accounts = snapshot.docs
          .map((doc) => Account.fromFirestore(doc))
          .toList();

      debugPrint('[FinanceService] Loaded ${accounts.length} accounts');
      return accounts;
    } catch (e) {
      debugPrint('[FinanceService] Error loading accounts: $e');
      return [];
    }
  }

  /// Get transactions with optional filters
  Future<List<finance.Transaction>> getTransactions({
    String? accountId,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) async {
    try {
      Query query = _userDoc.collection('transactions');

      if (accountId != null) {
        query = query.where('accountId', isEqualTo: accountId);
      }

      if (category != null) {
        query = query.where('category', isEqualTo: category);
      }

      if (startDate != null) {
        query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }

      if (endDate != null) {
        query = query.where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      query = query.orderBy('date', descending: true).limit(limit);

      final snapshot = await query.get();
      final transactions = snapshot.docs
          .map((doc) => finance.Transaction.fromFirestore(doc))
          .toList();

      debugPrint('[FinanceService] Loaded ${transactions.length} transactions');
      return transactions;
    } catch (e) {
      debugPrint('[FinanceService] Error loading transactions: $e');
      return [];
    }
  }

  /// Get monthly aggregate for a given period (e.g. '2026-03')
  Future<MonthlyAggregate?> getMonthlyAggregate(String period) async {
    try {
      // Backend stores as monthly_YYYY_MM
      final docId = 'monthly_${period.replaceAll('-', '_')}';
      final doc = await _userDoc
          .collection('financialAggregates')
          .doc(docId)
          .get();

      if (!doc.exists) {
        debugPrint('[FinanceService] No aggregate found for $period');
        return null;
      }

      final aggregate = MonthlyAggregate.fromFirestore(doc);
      debugPrint('[FinanceService] Loaded aggregate for $period: ${aggregate.transactionCount} transactions');
      return aggregate;
    } catch (e) {
      debugPrint('[FinanceService] Error loading aggregate for $period: $e');
      return null;
    }
  }

  /// Get aggregates for recent months
  Future<List<MonthlyAggregate>> getRecentAggregates({int months = 6}) async {
    try {
      final snapshot = await _userDoc
          .collection('financialAggregates')
          .where('type', isEqualTo: 'monthly')
          .orderBy(FieldPath.documentId, descending: true)
          .limit(months)
          .get();

      final aggregates = snapshot.docs
          .map((doc) => MonthlyAggregate.fromFirestore(doc))
          .toList();

      debugPrint('[FinanceService] Loaded ${aggregates.length} recent aggregates');
      return aggregates;
    } catch (e) {
      debugPrint('[FinanceService] Error loading recent aggregates: $e');
      return [];
    }
  }

  /// Ask AI a financial question
  Future<Map<String, dynamic>> askAI(String question, {String? sessionId}) async {
    debugPrint('[FinanceService] Asking AI: $question');
    await FirebaseAuth.instance.currentUser?.getIdToken(true);

    final result = await _functions
        .httpsCallable('askFinanceAI')
        .call({
      'question': question,
      if (sessionId != null) 'sessionId': sessionId,
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    debugPrint('[FinanceService] AI response received');
    return data;
  }

  /// Get all unique categories from the user's transactions
  Future<List<String>> getCategories() async {
    try {
      // Read from the aggregate to get category list rather than scanning all transactions
      final now = DateTime.now();
      final currentPeriod = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final aggregate = await getMonthlyAggregate(currentPeriod);

      if (aggregate != null && aggregate.categoryBreakdown.isNotEmpty) {
        final categories = aggregate.categoryBreakdown.keys.toList()..sort();
        return categories;
      }

      // Fallback: get a sample of transactions and extract categories
      final transactions = await getTransactions(limit: 100);
      final categorySet = <String>{};
      for (final t in transactions) {
        categorySet.add(t.category);
      }
      final categories = categorySet.toList()..sort();
      return categories;
    } catch (e) {
      debugPrint('[FinanceService] Error loading categories: $e');
      return [];
    }
  }
}
