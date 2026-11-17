import 'package:intl/intl.dart';

import 'recording_analysis.dart';

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
    'التسجيل': 'playback', 'المسجل': 'playback', 'recorded': 'playback', 'recording': 'playback',
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
      .replaceAllMapped(RegExp(r'\b(cam(?:era)?)(?=\d)'), (_) => 'cam ')
      .replaceAllMapped(RegExp(r'\b(?:oh|o) (\d)\b'), (m) => '0${m[1]}');
}

DateTime? _voiceDate(String text, DateTime now) {
  if (text == 'today') return DateTime(now.year, now.month, now.day);
  if (text == 'yesterday') return DateTime(now.year, now.month, now.day - 1);
  const ordinalDays = {
    'first': '1', 'second': '2', 'third': '3', 'fourth': '4', 'fifth': '5',
    'sixth': '6', 'seventh': '7', 'eighth': '8', 'ninth': '9', 'tenth': '10',
    'eleventh': '11', 'twelfth': '12', 'thirteenth': '13', 'fourteenth': '14',
    'fifteenth': '15', 'sixteenth': '16', 'seventeenth': '17',
    'eighteenth': '18', 'nineteenth': '19', 'twentieth': '20', 'thirtieth': '30',
  };
  final formatted = text
      .replaceAllMapped(RegExp(r'\b(?:(20|30)[ -])?([a-z]+)\b'), (m) {
        final day = ordinalDays[m[2]];
        if (day == null) return m[0]!;
        final tens = int.parse(m[1] ?? '0');
        return '${tens + int.parse(day)}';
      })
      .replaceAllMapped(RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)\b'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'[a-z]+'),
      (m) => m[0]![0].toUpperCase() + m[0]!.substring(1));
  for (final pattern in ['MMMM d yyyy', 'd MMMM yyyy', 'yyyy-MM-dd', 'd/M/yyyy']) {
    try {
      final date = DateFormat(pattern, 'en_US').parseStrict(formatted);
      if (date.year >= 2000) return date;
    } on FormatException {
      continue;
    }
  }
  for (final pattern in ['MMMM d', 'd MMMM']) {
    try {
      return DateFormat('$pattern yyyy', 'en_US')
          .parseStrict('$formatted ${now.year}');
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
      .replaceFirst(RegExp(r'^(?:can|could|would) you '), '')
      .replaceAll(RegExp(r'\b(?:please|me|the|on|at|for)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ').trim();
  final live = RegExp(
    r'^(?:(?:show|open|play|view)\s+)*(?:live\s+cam\s+(\d{1,3})|cam\s+(\d{1,3})\s+live)$',
  ).firstMatch(text);
  if (live != null) {
    final camera = int.parse(live[1] ?? live[2]!);
    return camera == 0 ? null : (camera: camera, start: null, end: null);
  }
  final playbackText = text
      .replaceAllMapped(RegExp(r'(^|[\s\d])([ap])\s*\.\s*m\.?(?=\s|$)'),
          (m) => '${m[1]}${m[2]}m')
      .replaceAllMapped(RegExp(r'\b(from|to)\s+(\d{1,2})(\d{2})(?=\s*(?:[ap]m\b|to\b|$))'),
          (m) => '${m[1]} ${m[2]}:${m[3]}')
      .replaceAllMapped(
        RegExp(r'^((?:show |open |play |playback |watch )*cam )(to|too)\s+(?=.+\bfrom\b)'),
        (m) => '${m[1]}2 ',
      );
  final playback = RegExp(
    r'^(?:(?:show|open|play|playback|watch)\s+)*cam\s+(\d{1,3})'
    r'(?:\s+playback)?(?:\s+(.+?))?\s+from\s+(.+?)\s+to\s+(.+)$',
  ).firstMatch(playbackText);
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
  final beforeDate = before == null ? null : _voiceDate(before, now);
  final afterDate = after == null ? null : _voiceDate(after, now);
  if ((before != null && beforeDate == null) ||
      (after != null && afterDate == null)) return null;
  final beforeRelative = before == 'today' || before == 'yesterday';
  final afterRelative = after == 'today' || after == 'yesterday';
  if (beforeDate != null && afterDate != null &&
      beforeRelative == afterRelative && beforeDate != afterDate) return null;
  final date = afterRelative ? beforeDate ?? afterDate : afterDate ?? beforeDate;
  if (date == null) return null;
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

final _analysisPrefix = RegExp(
    r'^(?:check|analy[sz]e|scan|show me what you detect on|'
    r'when did (?:a person|a vehicle) appear (?:on|in)|'
    r'find (?:people|vehicles) (?:on|in)|'
    r'فرجيني شو بتلقط عَ?|حلل|حلّل|حللي|فتش)\s+',
    caseSensitive: false,
  );

bool isRecordingAnalysisRequest(String transcript) => _analysisPrefix.hasMatch(transcript.trim());

({CameraVoiceCommand range, RecordingAnalysisFilter filter})?
    parseRecordingAnalysis(String transcript, DateTime now) {
  final prefix = _analysisPrefix.firstMatch(transcript.trim());
  if (prefix == null) return null;
  final action = prefix[0]!.toLowerCase();
  final filter = action.contains('person') || action.contains('people')
      ? RecordingAnalysisFilter.people
      : action.contains('vehicle')
          ? RecordingAnalysisFilter.vehicles
          : RecordingAnalysisFilter.all;
  final range = parseCameraVoiceCommand(
    transcript.trim().substring(prefix.end)
        .replaceAll('تشرين التاني', 'تشرين الثاني')
        .replaceAll(RegExp(r'(^|\s)التلاتة(?=\s|$)'), ' تلاتة')
        .replaceAllMapped(RegExp(r'(^|\s)للتلاتة(?=\s|$)'), (_) => ' لل تلاتة'),
    now,
  );
  if (range == null || range.start == null || range.end == null) return null;
  return (range: range, filter: filter);
}
