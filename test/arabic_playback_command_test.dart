import 'package:flutter_test/flutter_test.dart';
import 'package:zvektra/arabic_playback_command.dart';

void main() {
  test('parses the reported Lebanese Arabic playback command', () {
    expect(arabicPlaybackCommand('فرجيني كاميرا واحد مبارح من ١٢ للـ ١٢ وخمسة.'),
        'playback cam1 yesterday from 12:00 to 12:05');
  });

  test('accepts Arabic numerals and common colloquial time expressions', () {
    expect(arabicPlaybackCommand('ورجيني كاميرا رقم تلاتة اليوم من الساعة ٦ ونص لحد ۷:۱۵'),
        'playback cam3 today from 6:30 to 7:15');
  });

  test('rejects unknown words and invalid times', () {
    expect(arabicPlaybackCommand('فرجيني شي'), isNull);
    expect(arabicPlaybackCommand('فرجيني كاميرا اثنين من ١٢ الى ١٢:٧٠'), isNull);
  });
}
