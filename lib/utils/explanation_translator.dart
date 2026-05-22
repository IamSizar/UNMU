class ExplanationTranslator {
  // Translate common phrases in explanation/reason text
  static String translate(String text, bool isArabic) {
    if (!isArabic) return text;
    
    // Common phrase translations
    final translations = {
      'Sharia Compliance Analysis for': 'تحليل الامتثال الشرعي لـ',
      'Sharia Compliance Analysis': 'تحليل الامتثال الشرعي',
      'BUSINESS ACTIVITY SCREENING': 'فحص النشاط التجاري',
      'Business activity screening': 'فحص النشاط التجاري',
      'Business activity is compliant': 'النشاط التجاري متوافق',
      'Business activity information not available': 'معلومات النشاط التجاري غير متاحة',
      'Business activity: (allowed)': 'النشاط التجاري: (مسموح)',
      'Business activity:': 'النشاط التجاري:',
      'Business activity': 'النشاط التجاري',
      'FINANCIAL RATIO SCREENING': 'فحص النسب المالية',
      'Financial ratio screening': 'فحص النسب المالية',
      'Debt Ratio': 'نسبة الدين',
      'Debt ratio': 'نسبة الدين',
      'Debt ratio:': 'نسبة الدين:',
      'Not available': 'غير متاح',
      'not available': 'غير متاح',
      ': Not available': ': غير متاح',
      ': not available': ': غير متاح',
      'Within limit': 'ضمن الحد',
      'Exceeds limit': 'يتجاوز الحد',
      'Non-Compliant Income Ratio': 'نسبة الدخل غير المتوافق',
      'Non-compliant income': 'الدخل غير المتوافق',
      'Non-compliant income ratio': 'نسبة الدخل غير المتوافق',
      'Non-compliant income:': 'الدخل غير المتوافق:',
      'Non-compliant income ratio:': 'نسبة الدخل غير المتوافق:',
      'Within acceptable limit (≤5%)': 'ضمن الحد المقبول (≤5%)',
      'Within acceptable limit (<=5%)': 'ضمن الحد المقبول (<=5%)',
      'within acceptable limit (≤5%)': 'ضمن الحد المقبول (≤5%)',
      'within acceptable limit (<=5%)': 'ضمن الحد المقبول (<=5%)',
      'Within acceptable limit': 'ضمن الحد المقبول',
      'Requires purification': 'يتطلب التطهير',
      'minor - acceptable with purification': 'بسيط - مقبول مع التطهير',
      'FINAL ASSESSMENT': 'التقييم النهائي',
      'Final assessment': 'التقييم النهائي',
      'Final grade': 'الدرجة النهائية',
      'Status:': 'الحالة:',
      'Grade:': 'الدرجة:',
      'This stock is fully compliant with Sharia principles': 'هذا السهم متوافق بالكامل مع مبادئ الشريعة',
      'This stock is fully compliant with Sharia': 'هذا السهم متوافق بالكامل مع الشريعة',
      'This stock is fully compliant': 'هذا السهم متوافق بالكامل',
      'This stock is': 'هذا السهم',
      'This stock': 'هذا السهم',
      'with Sharia principles': 'مع مبادئ الشريعة',
      'with Sharia': 'مع الشريعة',
      'fully compliant with Sharia': 'متوافق بالكامل مع الشريعة',
      'fully compliant with Sharia principles': 'متوافق بالكامل مع مبادئ الشريعة',
      'is fully compliant with Sharia principles': 'متوافق بالكامل مع مبادئ الشريعة',
      'is fully compliant with Sharia': 'متوافق بالكامل مع الشريعة',
      'is fully compliant': 'متوافق بالكامل',
      'All financial ratios are within acceptable limits': 'جميع النسب المالية ضمن الحدود المقبولة',
      'No purification required': 'لا يتطلب التطهير',
      'This stock requires purification': 'هذا السهم يتطلب التطهير',
      'of non-compliant income': 'من الدخل غير المتوافق',
      'Investment is permissible after purification': 'الاستثمار جائز بعد التطهير',
      'This stock is not Sharia compliant': 'هذا السهم غير متوافق مع الشريعة',
      'Investment is not permissible': 'الاستثمار غير جائز',
      'Insufficient data for complete assessment': 'بيانات غير كافية للتقييم الكامل',
      'DETAILED REASONING': 'المنطق التفصيلي',
      'Detailed reasoning': 'المنطق التفصيلي',
      'DATA SOURCE': 'مصدر البيانات',
      'Data source': 'مصدر البيانات',
      'Source:': 'المصدر:',
      'As of:': 'اعتباراً من:',
      'Result:': 'النتيجة:',
      'Sector:': 'القطاع:',
      'Industry:': 'الصناعة:',
      'Halal - Fully compliant': 'حلال - متوافق بالكامل',
      'Mixed - Requires purification': 'مختلط - يتطلب التطهير',
      'Not Halal - Debt ratio too high': 'غير حلال - نسبة الدين مرتفعة جداً',
      'Not Halal - Non-compliant income too high': 'غير حلال - الدخل غير المتوافق مرتفع جداً',
      'Mixed - Requires purification of': 'مختلط - يتطلب التطهير من',
      'must be donated to charity': 'يجب التبرع به للجمعيات الخيرية',
      'of income must be donated': 'من الدخل يجب التبرع به',
    };
    
    String translated = text;
    
    // Apply translations (longer phrases first to avoid partial matches)
    final sortedKeys = translations.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    
    for (final key in sortedKeys) {
      translated = translated.replaceAll(key, translations[key]!);
    }
    
    // Translate common patterns
    translated = _translatePatterns(translated, isArabic);
    
    return translated;
  }
  
  static String _translatePatterns(String text, bool isArabic) {
    if (!isArabic) return text;
    
    // Translate percentage patterns
    text = text.replaceAllMapped(
      RegExp(r'(\d+\.?\d*)%'),
      (match) => '${match.group(1)}%',
    );
    
    // Translate "≤" and ">=" patterns
    text = text.replaceAll('≤', 'أقل من أو يساوي');
    text = text.replaceAll('>=', 'أكبر من أو يساوي');
    text = text.replaceAll('>', 'أكبر من');
    text = text.replaceAll('<', 'أقل من');
    
    // Translate common status phrases
    text = text.replaceAll('HALAL', 'حلال');
    text = text.replaceAll('HARAM', 'حرام');
    text = text.replaceAll('MIXED', 'مختلط');
    text = text.replaceAll('UNKNOWN', 'غير معروف');
    
    // Handle mixed English/Arabic text - translate "This stock is" followed by any text (including Arabic)
    text = text.replaceAllMapped(
      RegExp(r'This stock is\s+([^\n\.]+)', caseSensitive: false),
      (match) {
        final followingText = match.group(1)!.trim();
        // If the following text is already in Arabic, just add "هذا السهم" before it
        if (RegExp(r'[\u0600-\u06FF]').hasMatch(followingText)) {
          return 'هذا السهم $followingText';
        }
        // Otherwise, translate the whole phrase
        return 'هذا السهم $followingText';
      },
    );
    
    // Translate "is" when it appears before Arabic text (common pattern)
    text = text.replaceAllMapped(
      RegExp(r'\bis\s+([\u0600-\u06FF][^\n\.]*)', caseSensitive: false),
      (match) => match.group(1)!,
    );
    
    // Translate standalone "is" at start of sentences (but not if followed by Arabic)
    text = text.replaceAllMapped(
      RegExp(r'\.\s*is\s+([^\u0600-\u06FF])', caseSensitive: false),
      (match) => '. ${match.group(1)!}',
    );
    
    // Clean up any remaining "This stock is" patterns (case insensitive)
    text = text.replaceAll(RegExp(r'This stock is\s*', caseSensitive: false), 'هذا السهم ');
    
    // Clean up any remaining standalone "is" (not part of a word)
    text = text.replaceAllMapped(
      RegExp(r'\bis\s+(?![a-zA-Z])', caseSensitive: false),
      (match) => '',
    );
    
    // Translate grade patterns
    text = text.replaceAllMapped(
      RegExp(r'Grade ([ABCDF])'),
      (match) => 'الدرجة ${match.group(1)}',
    );
    
    // Translate "A (Halal - Fully compliant)" pattern
    text = text.replaceAllMapped(
      RegExp(r'([ABCDF])\s*\(([^)]+)\)'),
      (match) {
        final grade = match.group(1)!;
        final status = match.group(2)!;
        String translatedStatus = status;
        if (status.contains('Halal - Fully compliant')) {
          translatedStatus = 'حلال - متوافق بالكامل';
        } else if (status.contains('Mixed - Requires purification')) {
          translatedStatus = 'مختلط - يتطلب التطهير';
        } else if (status.contains('Not Halal')) {
          translatedStatus = 'غير حلال';
        }
        return '$grade ($translatedStatus)';
      },
    );
    
    return text;
  }
}

