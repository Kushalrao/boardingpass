import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyAggregate {
  final String period; // e.g. '2026-03'
  final double totalSpending;
  final double totalIncome;
  final double netFlow;
  final int transactionCount;
  final Map<String, CategoryStats> categoryBreakdown;
  final Map<String, MerchantStats> merchantBreakdown;

  MonthlyAggregate({
    required this.period,
    required this.totalSpending,
    required this.totalIncome,
    required this.netFlow,
    required this.transactionCount,
    required this.categoryBreakdown,
    required this.merchantBreakdown,
  });

  factory MonthlyAggregate.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final categoryMap = <String, CategoryStats>{};
    final rawCategories = data['categoryBreakdown'] as Map<String, dynamic>? ?? {};
    for (final entry in rawCategories.entries) {
      categoryMap[entry.key] = CategoryStats.fromJson(entry.value as Map<String, dynamic>);
    }

    final merchantMap = <String, MerchantStats>{};
    final rawMerchants = data['merchantBreakdown'] as Map<String, dynamic>? ?? {};
    for (final entry in rawMerchants.entries) {
      merchantMap[entry.key] = MerchantStats.fromJson(entry.value as Map<String, dynamic>);
    }

    return MonthlyAggregate(
      period: doc.id,
      totalSpending: (data['totalSpending'] as num?)?.toDouble() ?? 0.0,
      totalIncome: (data['totalIncome'] as num?)?.toDouble() ?? 0.0,
      netFlow: (data['netFlow'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (data['transactionCount'] as num?)?.toInt() ?? 0,
      categoryBreakdown: categoryMap,
      merchantBreakdown: merchantMap,
    );
  }

  factory MonthlyAggregate.empty(String period) {
    return MonthlyAggregate(
      period: period,
      totalSpending: 0.0,
      totalIncome: 0.0,
      netFlow: 0.0,
      transactionCount: 0,
      categoryBreakdown: {},
      merchantBreakdown: {},
    );
  }

  /// Get top N categories sorted by total spending
  List<MapEntry<String, CategoryStats>> topCategories(int n) {
    final sorted = categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return sorted.take(n).toList();
  }

  /// Get top N merchants sorted by total spending
  List<MapEntry<String, MerchantStats>> topMerchants(int n) {
    final sorted = merchantBreakdown.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return sorted.take(n).toList();
  }
}

class CategoryStats {
  final double total;
  final int count;
  final double avgTransaction;

  CategoryStats({
    required this.total,
    required this.count,
    required this.avgTransaction,
  });

  factory CategoryStats.fromJson(Map<String, dynamic> json) {
    final total = (json['total'] as num?)?.toDouble() ?? 0.0;
    final count = (json['count'] as num?)?.toInt() ?? 0;
    final avg = (json['avgTransaction'] as num?)?.toDouble() ?? (count > 0 ? total / count : 0.0);
    return CategoryStats(
      total: total,
      count: count,
      avgTransaction: avg,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'count': count,
      'avgTransaction': avgTransaction,
    };
  }
}

class MerchantStats {
  final double total;
  final int count;

  MerchantStats({
    required this.total,
    required this.count,
  });

  factory MerchantStats.fromJson(Map<String, dynamic> json) {
    return MerchantStats(
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'count': count,
    };
  }
}
