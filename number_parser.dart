/// تحويل الكلام المنطوق (عربي فصيح / دارجة جزائرية / فرنسية / أرقام) إلى نقطة من 0 إلى 20.
enum VoiceCommand { confirm, back, skip }

class NumberParser {
  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _easternDigits = '۰۱۲۳۴۵۶۷۸۹';

  /// الحد الأقصى المسموح للنقطة.
  static const double maxScore = 20;

  static final Map<String, int> _words = _buildWords();

  static Map<String, int> _buildWords() {
    final m = <String, int>{};
    void add(int v, List<String> ws) {
      for (final w in ws) {
        m[w] = v;
      }
    }

    add(0, ['صفر', 'zero', 'سيرو']);
    add(1, ['واحد', 'واحده', 'وحد', 'احد', 'un', 'une', 'one']);
    add(2, ['اثنان', 'اثنين', 'اثنا', 'اثنتان', 'زوج', 'زوز', 'deux', 'two']);
    add(3, ['ثلاثه', 'ثلاث', 'تلاته', 'تلاتا', 'trois', 'three']);
    add(4, ['اربعه', 'اربع', 'quatre', 'four']);
    add(5, ['خمسه', 'خمس', 'cinq', 'five']);
    add(6, ['سته', 'ست', 'six']);
    add(7, ['سبعه', 'سبع', 'sept', 'seven']);
    add(8, ['ثمانيه', 'ثماني', 'ثمان', 'تمانيه', 'تمنيه', 'huit', 'eight']);
    add(9, ['تسعه', 'تسع', 'neuf', 'nine']);
    add(10, ['عشره', 'عشر', 'dix', 'ten']);
    add(11, ['حداش', 'حداشر', 'احداش', 'onze']);
    add(12, ['طناش', 'اطناش', 'douze']);
    add(13, ['تلطاش', 'تلتاش', 'ثلطاش', 'treize']);
    add(14, ['اربعطاش', 'ربعطاش', 'quatorze']);
    add(15, ['خمسطاش', 'خمستاش', 'quinze']);
    add(16, ['سطاش', 'ستاش', 'seize']);
    add(17, ['سبعطاش', 'سبعتاش']);
    add(18, ['تمنطاش', 'تمنتاش', 'ثمنطاش']);
    add(19, ['تسعطاش', 'تسعتاش']);
    add(20, ['عشرين', 'عشرون', 'vingt', 'twenty']);
    return m;
  }

  static const _tenWords = {'عشر', 'عشره'};
  static const _halfWords = {'نصف', 'نص', 'demi', 'demie', 'half'};
  static const _quarterWords = {'ربع', 'quart'};
  static const _pointWords = {'فاصله', 'فاصل', 'فاصلة', 'virgule', 'point', 'نقطه'};

  static const _confirmWords = {
    'تاكيد', 'اكد', 'احفظ', 'حفظ', 'التالي', 'تالي', 'ok', 'okay', 'valide', 'suivant', 'confirm'
  };
  static const _backWords = {'السابق', 'سابق', 'ارجع', 'رجوع', 'retour', 'back'};
  static const _skipWords = {'تجاوز', 'تخطي', 'غائب', 'غايب', 'absent', 'skip'};

  /// تطبيع النص: أرقام عربية→لاتينية، إزالة التشكيل، توحيد الهمزات والتاء المربوطة.
  static String normalize(String s) {
    var t = s.toLowerCase();
    for (var i = 0; i < 10; i++) {
      t = t.replaceAll(_arabicDigits[i], '$i').replaceAll(_easternDigits[i], '$i');
    }
    t = t.replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.');
    t = t.replaceAll(RegExp('[ً-ٰٟـ]'), '');
    t = t.replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    t = t.replaceAll('-', ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static int? _lookup(String tok) {
    final direct = _words[tok];
    if (direct != null) return direct;
    // كلمة ملصوقة بواو العطف مثل «وخمسة»
    if (tok.length > 2 && tok.startsWith('و')) return _words[tok.substring(1)];
    return null;
  }

  static bool _isIn(Set<String> set, String tok) {
    if (set.contains(tok)) return true;
    return tok.length > 2 && tok.startsWith('و') && set.contains(tok.substring(1));
  }

  /// يعيد النقطة أو null إن لم يفهم الكلام.
  static double? parse(String input) {
    final s = normalize(input);
    if (s.isEmpty) return null;
    final tokens = s.split(' ');

    double? base;
    int idx = -1;

    // 1) أرقام مكتوبة
    final m = RegExp(r'(?<!\d)(\d{1,2}(?:\.\d{1,2})?)(?!\d)').firstMatch(s);
    if (m != null) {
      base = double.tryParse(m.group(1)!);
      final before = s.substring(0, m.end);
      idx = before.trim().isEmpty ? -1 : before.trim().split(' ').length - 1;
    } else {
      // 2) كلمات
      for (var i = 0; i < tokens.length; i++) {
        final v = _lookup(tokens[i]);
        if (v == null) continue;
        var val = v;
        idx = i;
        if (i + 1 < tokens.length) {
          final next = tokens[i + 1];
          if (val >= 1 && val <= 9 && _tenWords.contains(next)) {
            // خمسة عشر، ثلاثة عشر، أحد عشر...
            val = 10 + val;
            idx = i + 1;
          } else if (val == 10 && _words[next] != null && _words[next]! >= 7 && _words[next]! <= 9) {
            // dix sept, dix huit, dix neuf
            val = 10 + _words[next]!;
            idx = i + 1;
          }
        }
        base = val.toDouble();
        break;
      }
    }
    if (base == null) return null;

    // 3) كسور بعد الرقم: ونصف، وربع، فاصلة خمسة
    var result = base;
    for (var j = idx + 1; j < tokens.length; j++) {
      final t = tokens[j];
      if (_isIn(_halfWords, t)) {
        if (result == result.truncateToDouble()) result += 0.5;
        break;
      }
      if (_isIn(_quarterWords, t)) {
        if (result == result.truncateToDouble()) result += 0.25;
        break;
      }
      if (_pointWords.contains(t) && j + 1 < tokens.length) {
        final d = RegExp(r'^\d$').hasMatch(tokens[j + 1])
            ? int.parse(tokens[j + 1])
            : _lookup(tokens[j + 1]);
        if (d != null && d >= 0 && d <= 9 && result == result.truncateToDouble()) {
          result += d / 10;
        }
        break;
      }
    }

    if (result < 0 || result > maxScore) return null;
    return result;
  }

  /// أوامر صوتية: تأكيد / السابق / تجاوز (فقط إذا لم تكن هناك نقطة).
  static VoiceCommand? command(String input) {
    final s = normalize(input);
    if (s.isEmpty || parse(input) != null) return null;
    for (final t in s.split(' ')) {
      if (_confirmWords.contains(t)) return VoiceCommand.confirm;
      if (_backWords.contains(t)) return VoiceCommand.back;
      if (_skipWords.contains(t)) return VoiceCommand.skip;
    }
    return null;
  }
}
