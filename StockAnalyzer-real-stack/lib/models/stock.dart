class Stock {
  final int id;
  final String ticker;
  final String exchange;
  final String name;
  final String? country;
  final String? regionCode;
  final String? sector;
  final String? industry;
  final String? description;

  Stock({
    required this.id,
    required this.ticker,
    required this.exchange,
    required this.name,
    this.country,
    this.regionCode,
    this.sector,
    this.industry,
    this.description,
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      id: json['id'] as int,
      ticker: json['ticker'] as String,
      exchange: json['exchange'] as String,
      name: json['name'] as String,
      country: json['country'] as String?,
      regionCode: json['region_code'] as String?,
      sector: json['sector'] as String?,
      industry: json['industry'] as String?,
      description: json['description'] as String?,
    );
  }
}

class ShariahStatus {
  final String status;
  final String grade;
  final double? debtRatio;
  final double? haramIncomeRatio;
  final double? purificationRate;
  final String explanation;
  final String? asOfDate;

  ShariahStatus({
    required this.status,
    required this.grade,
    this.debtRatio,
    this.haramIncomeRatio,
    this.purificationRate,
    required this.explanation,
    this.asOfDate,
  });

  factory ShariahStatus.fromJson(Map<String, dynamic> json) {
    return ShariahStatus(
      status: json['status'] as String,
      grade: json['grade'] as String,
      debtRatio: json['debt_ratio'] != null
          ? (json['debt_ratio'] as num).toDouble()
          : null,
      haramIncomeRatio: json['haram_income_ratio'] != null
          ? (json['haram_income_ratio'] as num).toDouble()
          : null,
      purificationRate: json['purification_rate'] != null
          ? (json['purification_rate'] as num).toDouble()
          : null,
      explanation: json['explanation'] as String,
      asOfDate: json['as_of_date'] as String?,
    );
  }

  // Color mapping for grades
  static int getGradeColor(String grade) {
    switch (grade) {
      case 'A':
        return 0xFF4CAF50; // Green
      case 'B':
        return 0xFFFFEB3B; // Yellow
      case 'C':
        return 0xFFFF9800; // Orange
      case 'D':
        return 0xFFFF5722; // Deep Orange/Red-Orange for Warning
      case 'F':
        return 0xFFF44336; // Red
      default:
        return 0xFF9E9E9E; // Grey
    }
  }
}

class Fundamentals {
  final double? totalAssets;
  final double? totalDebt;
  final double? cashAndEquiv;
  final double? totalRevenue;
  final double? interestIncome;
  final double? interestExpense;
  final double? netIncome;
  final double? dividendsPerShare;
  final String? asOfDate;
  final String? source;

  Fundamentals({
    this.totalAssets,
    this.totalDebt,
    this.cashAndEquiv,
    this.totalRevenue,
    this.interestIncome,
    this.interestExpense,
    this.netIncome,
    this.dividendsPerShare,
    this.asOfDate,
    this.source,
  });

  factory Fundamentals.fromJson(Map<String, dynamic> json) {
    return Fundamentals(
      totalAssets: json['total_assets'] != null
          ? (json['total_assets'] as num).toDouble()
          : null,
      totalDebt: json['total_debt'] != null
          ? (json['total_debt'] as num).toDouble()
          : null,
      cashAndEquiv: json['cash_and_equiv'] != null
          ? (json['cash_and_equiv'] as num).toDouble()
          : null,
      totalRevenue: json['total_revenue'] != null
          ? (json['total_revenue'] as num).toDouble()
          : null,
      interestIncome: json['interest_income'] != null
          ? (json['interest_income'] as num).toDouble()
          : null,
      interestExpense: json['interest_expense'] != null
          ? (json['interest_expense'] as num).toDouble()
          : null,
      netIncome: json['net_income'] != null
          ? (json['net_income'] as num).toDouble()
          : null,
      dividendsPerShare: json['dividends_per_share'] != null
          ? (json['dividends_per_share'] as num).toDouble()
          : null,
      asOfDate: json['as_of_date'] as String?,
      source: json['source'] as String?,
    );
  }

  // Format large numbers (billions, millions)
  static String formatCurrency(double? value) {
    if (value == null) return 'N/A';
    if (value >= 1000000000) {
      return '\$${(value / 1000000000).toStringAsFixed(2)}B';
    } else if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '\$${(value / 1000).toStringAsFixed(2)}K';
    }
    return '\$${value.toStringAsFixed(2)}';
  }
}
