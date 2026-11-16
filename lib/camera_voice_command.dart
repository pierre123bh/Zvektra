import 'package:intl/intl.dart';

enum VoiceLanguage {
  lebanese('ar-LB', 'Lebanese Arabic'),
  english('en-US', 'English');

  const VoiceLanguage(this.locale, this.label);
  final String locale;
  final String label;

  String say(String english, String arabic) =>
      this == VoiceLanguage.lebanese ? arabic : english;
}

typedef CameraVoiceCommand = ({int camera, DateTime? start, DateTime? end});

const _numbers = {
  'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
  'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
  'ten': '10', 'eleven': '11', 'twelve': '12', 'fifteen': '15',
  'twenty': '20', 'thirty': '30', 'forty': '40', 'fifty': '50',
  'صفر': '0', 'واحد': '1', 'واحدة': '1', 'اول': '1',
  'اثنين': '2', 'اثنان': '2', 'اتنين': '2', 'تنين': '2',
  'تلاتة': '3', 'تلات': '3', 'ثلاثة': '3', 'ثلاث': '3',
  'اربعة': '4', 'اربع': '4', 'خمسة': '5', 'خمس': '5', 'ستة': '6',
  'ست': '6', 'سبعة': '7', 'سبع': '7', 'تمانية': '8', 'ثمانية': '8',
  'تسعة': '9', 'عشرة': '10', 'حدعش': '11', 'طنعش': '12',
  'اتناشر': '12', 'تنعش': '12', 'ربع': '15', 'عشرين': '20',
  'نص': '30', 'نصف': '30',
};

String _normalize(String input) {
  const digits = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  var text = input.toLowerCase()
      .replaceAllMapped(RegExp('[$digits]'), (m) => (digits.indexOf(m[0]!) % 10).toString())
      .replaceAll(RegExp(r'[\u061C\u0640\u064B-\u065F\u0670\u200E\u200F]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[،,؟!?]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'\.$'), '');
  const phrases = {
    'بعد الظهر': 'pm', 'بعد الضهر': 'pm', 'بعد الظهرية': 'pm',
    'قبل الظهر': 'am', 'بعد العصر': 'pm', 'a.m.': 'am', 'p.m.': 'pm',
    'a m': 'am', 'p m': 'pm', 'play back': 'playback', 'و نص': 'and 30',
    'بلاي باك': 'playback', 'كانون الثاني': 'january', 'كانون الاول': 'december',
    'تشرين الاول': 'october', 'تشرين الثاني': 'november',
  };
  final phrasePattern = phrases.keys.map(RegExp.escape).join('|');
  text = text.replaceAllMapped(
      RegExp('(^|\\s|\\d)($phrasePattern)(?=\\s|\$)'),
      (m) => '${m[1]}${phrases[m[2]]}');
  const words = {
    'camera': 'cam', 'channel': 'cam', 'kamera': 'cam',
    'كاميرا': 'cam', 'كامرة': 'cam',
    'رقم': '', 'number': '', 'بتاريخ': '', 'الساعة': '', 'ساعة': '',
    'فرجيني': 'show', 'فرجني': 'show', 'ورجيني': 'show', 'ورجني': 'show',
    'fergini': 'show', 'farjini': 'show', 'شغل': 'show', 'اعرض': 'show',
    'افتح': 'show', 'مباشر': 'live', 'لايف': 'live', 'تسجيل': 'playback',
    'التسجيل': 'playback', 'المسجل': 'playback', 'recorded': 'playback',
    'مبارح': 'yesterday', 'امبارح': 'yesterday', 'البارحة': 'yesterday',
    'البارحه': 'yesterday', 'امس': 'yesterday', 'اليوم': 'today',
    'من': 'from', 'للساعة': 'to', 'لساعة': 'to', 'ل': 'to', 'لل': 'to', 'لحد': 'to', 'لغاية': 'to',
    'الي': 'to', 'until': 'to', 'through': 'to',
    'الصبح': 'am', 'صباحا': 'am', 'صبح': 'am', 'المسا': 'pm',
    'مساء': 'pm', 'مساءا': 'pm', 'الليل': 'pm',
    'يناير': 'january', 'فبراير': 'february', 'شباط': 'february',
    'مارس': 'march', 'اذار': 'march', 'ابريل': 'april', 'نيسان': 'april',
    'مايو': 'may', 'ايار': 'may', 'يونيو': 'june', 'حزيران': 'june',
    'يوليو': 'july', 'تموز': 'july', 'اغسطس': 'august', 'اب': 'august',
    'سبتمبر': 'september', 'ايلول': 'september', 'اكتوبر': 'october',
    'نوفمبر': 'november', 'ديسمبر': 'december',
  };
  text = text.replaceAllMapped(RegExp(r'(^|\s)لل?(?=\d)'), (m) => '${m[1]}to ');
  return text.split(' ').map((word) {
    if (word.startsWith('و') && word.length > 1) {
      final minute = word.substring(1);
      final number = _numbers[minute] ?? (int.tryParse(minute) == null ? null : minute);
      if (number != null) return 'and $number';
    }
    return words[word] ?? _numbers[word] ?? (word == 'و' ? 'and' : word);
  }).where((word) => word.isNotEmpty).join(' ')
      .replaceAllMapped(RegExp(r'\b(cam(?:era)?)(?=\d)'), (_) => 'cam ');
}

DateTime? _voiceDate(String text, DateTime now) {
  if (text == 'today') return DateTime(now.year, now.month, now.day);
  if (text == 'yesterday') return DateTime(now.year, now.month, now.day - 1);
  final formatted = text.replaceAllMapped(RegExp(r'[a-z]+'),
      (m) => m[0]![0].toUpperCase() + m[0]!.substring(1));
  for (final pattern in ['MMMM d yyyy', 'd MMMM yyyy', 'yyyy-MM-dd', 'd/M/yyyy']) {
    try {
      final date = DateFormat(pattern, 'en_US').parseStrict(formatted);
      if (date.year >= 2000) return date;
    } on FormatException {
      continue;
    }
  }
  return null;
}

({int hour, int minute, String? period})? _voiceClock(String text) {
  final match = RegExp(r'^(\d{1,2})(?:(?::|\s+(?:and\s+)?)(\d{1,2}))?\s*(am|pm)?$')
      .firstMatch(text.trim());
  if (match == null) return null;
  final hour = int.parse(match[1]!);
  final minute = int.parse(match[2] ?? '0');
  final period = match[3];
  if (minute > 59 || hour > 23 || (period != null && (hour < 1 || hour > 12))) {
    return null;
  }
  return (hour: hour, minute: minute, period: period);
}

CameraVoiceCommand? parseCameraVoiceCommand(String transcript, DateTime now) {
  final text = _normalize(transcript)
      .replaceAll(RegExp(r'\b(?:please|me|the|on|at|for)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ').trim();
  final live = RegExp(r'^(?:(?:show|open|play|live|view)\s+)*cam\s+(\d{1,3})(?:\s+live)?$')
      .firstMatch(text);
  if (live != null) {
    final camera = int.parse(live[1]!);
    return camera == 0 ? null : (camera: camera, start: null, end: null);
  }
  final playback = RegExp(
    r'^(?:(?:show|open|play|playback|watch)\s+)*cam\s+(\d{1,3})'
    r'(?:\s+playback)?(?:\s+(.+?))?\s+from\s+(.+?)\s+to\s+(.+)$',
  ).firstMatch(text);
  if (playback == null) return null;
  final camera = int.parse(playback[1]!);
  if (camera == 0) return null;
  final startClock = _voiceClock(playback[3]!);
  if (startClock == null) return null;
  final endAndDate = RegExp(r'^(\d{1,2}(?:(?::|\s+(?:and\s+)?)(\d{1,2})(?![\d/.-]))?\s*(?:am|pm)?)(?:\s+(.+))?$')
      .firstMatch(playback[4]!);
  if (endAndDate == null) return null;
  final endClock = _voiceClock(endAndDate[1]!);
  if (endClock == null) return null;
  final before = playback[2];
  final after = endAndDate[3];
  final date = _voiceDate(after ?? before ?? '', now);
  if (date == null) return null;
  if (before != null && after != null && before != 'today' &&
      before != 'yesterday' && _voiceDate(before, now) != date) return null;
  DateTime at(int hour, int minute, String? period) => DateTime(
      date.year, date.month, date.day,
      period == null ? hour : hour % 12 + (period == 'pm' ? 12 : 0), minute);
  final fromPeriod = startClock.period ?? (startClock.hour >= 1 && startClock.hour <= 12 ? endClock.period : null);
  final toPeriod = endClock.period ?? (endClock.hour >= 1 && endClock.hour <= 12 ? startClock.period : null);
  final start = at(startClock.hour, startClock.minute, fromPeriod);
  final end = at(endClock.hour, endClock.minute, toPeriod);
  if (!end.isAfter(start) || end.isAfter(now)) return null;
  return (camera: camera, start: start, end: end);
}
