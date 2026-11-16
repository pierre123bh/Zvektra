const _numbers = {
  'واحد': 1, 'واحدة': 1, 'اول': 1,
  'اثنين': 2, 'اتنين': 2, 'تنين': 2,
  'ثلاثة': 3, 'تلاتة': 3, 'ثلاث': 3, 'تلات': 3,
  'اربعة': 4, 'اربع': 4, 'خمسة': 5, 'خمس': 5,
  'ستة': 6, 'ست': 6, 'سبعة': 7, 'سبع': 7, 'ثمانية': 8, 'تمانية': 8,
  'تسعة': 9, 'عشرة': 10, 'حدعش': 11, 'طنعش': 12, 'اتناشر': 12,
  'ربع': 15, 'عشرين': 20, 'نص': 30, 'نصف': 30,
};

String? arabicPlaybackCommand(String raw) {
  const digits = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  final text = raw
      .replaceAllMapped(RegExp('[$digits]'), (m) => (digits.indexOf(m[0]!) % 10).toString())
      .replaceAll(RegExp(r'[\u061C\u0640\u064B-\u065F\u0670\u200E\u200F]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[.،,؟!?]+$'), '')
      .trim();
  final match = RegExp(
    r'^(?:(?:فرجيني|فرجني|ورجيني|ورجني|شغل|اعرض|افتح)\s+)?'
    r'(?:كاميرا|كامرة)\s+(?:رقم\s+)?(\S+)\s+'
    r'(?:(مبارح|امبارح|البارحة|امس|اليوم)\s+)?'
    r'من\s+(?:الساعة\s+)?(.+?)\s+(?:الي|لحد|لل?)\s*'
    r'(?:الساعة\s+)?(.+?)$',
  ).firstMatch(text);
  if (match == null) return null;

  int? number(String value) => int.tryParse(value) ?? _numbers[value];
  String? clock(String value) {
    final parts = RegExp(r'^(\S+?)(?::(\d{1,2})|\s+و\s*(\S+))?$').firstMatch(value);
    if (parts == null) return null;
    final hour = number(parts[1]!);
    final minutes = number(parts[2] ?? parts[3] ?? '0');
    if (hour == null || hour < 0 || hour > 23 || minutes == null ||
        minutes < 0 || minutes > 59) return null;
    return '$hour:${minutes.toString().padLeft(2, '0')}';
  }

  final camera = number(match[1]!);
  final start = clock(match[3]!);
  final end = clock(match[4]!);
  if (camera == null || camera < 1 || start == null || end == null) return null;
  final day = match[2];
  final date = day == null ? '' : (day == 'اليوم' ? ' today' : ' yesterday');
  return 'playback cam$camera$date from $start to $end';
}
