import 'package:flutter_test/flutter_test.dart';
import 'package:zvektra/main.dart';

void main() {
  const device = Nvr(id: 'test', name: 'Test', manufacturer: 'Dahua',
      port: '1554', username: 'test user', maxChannels: 8);
  test('Dahua live uses the entered port and escapes credentials', () {
    final url = StreamBuilderService.url(device, 3, password: 'test@:/');
    expect(url, 'rtsp://test%20user:test%40%3A%2F@zvektra.net:1554/cam/realmonitor?channel=3&subtype=1');
  });
  test('Dahua recording preserves the requested interval', () {
    final url = StreamBuilderService.url(device, 5, password: 'test',
        start: DateTime(2026, 11, 6, 14), end: DateTime(2026, 11, 6, 14, 10));
    expect(url, contains('channel=5&starttime=2026_11_06_14_00_00&endtime=2026_11_06_14_10_00'));
  });
  test('Unverified vendor playback is not presented as supported', () {
    for (final vendor in ['Hikvision', 'Uniview', 'MEye']) {
      expect(StreamBuilderService.url(device.copyWith(manufacturer: vendor), 1,
          password: 'test', start: DateTime(2026)), isNull);
    }
  });
  test('Topcam uses the configured port and channel for both live routes', () {
    final topcam = device.copyWith(manufacturer: 'Topcam');
    expect(StreamBuilderService.url(topcam, 3, password: 'a/b'),
        'rtsp://zvektra.net:1554/user=test%20user_password=a%2Fb_channel=3_stream=0.sdp');
    expect(StreamBuilderService.url(topcam, 3, password: 'a/b', topcamFallback: true),
        'rtsp://test%20user:a%2Fb@zvektra.net:1554/Streaming/Channels/301');
  });

  test('Topcam playback preserves recorder-local time and uses UTC for the fallback', () {
    final topcam = device.copyWith(manufacturer: 'Topcam');
    final start = DateTime(2026, 11, 16, 8);
    final end = DateTime(2026, 11, 16, 9);
    final primary = StreamBuilderService.url(topcam, 2, password: 'test', start: start, end: end);
    expect(primary,
        'rtsp://test%20user:test@zvektra.net:1554/playback/ch2?starttime=2026_11_16_08_00_00&endtime=2026_11_16_09_00_00');
    final fallback = Uri.parse(StreamBuilderService.url(topcam, 2, password: 'test',
        start: start, end: end, topcamFallback: true)!);
    String iso(DateTime time) => time.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]|\.000'), '');
    expect(fallback.path, '/Streaming/tracks/201');
    expect(fallback.queryParameters, {'starttime': iso(start), 'endtime': iso(end)});
  });

}
