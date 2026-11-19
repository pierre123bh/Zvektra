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
  test('Hikvision playback uses UTC, the requested camera and entered port', () {
    final nvr = device.copyWith(manufacturer: 'Hikvision');
    final url = Uri.parse(StreamBuilderService.url(nvr, 7, password: 'a@b',
        start: DateTime.parse('2026-11-19T12:00:00+02:00'),
        end: DateTime.parse('2026-11-19T12:02:00+02:00'))!);
    expect(url.port, 1554);
    expect(url.path, '/Streaming/tracks/701');
    expect(url.queryParameters, {'starttime': '20261119T100000Z', 'endtime': '20261119T100200Z'});
    expect(StreamBuilderService.alternate(nvr, 7, password: 'a@b',
        start: DateTime.utc(2026, 11, 19)), contains('/ISAPI/Streaming/tracks/701'));
  });
  test('Uniview supports live and epoch-based recording ranges', () {
    final nvr = device.copyWith(manufacturer: 'Uniview');
    expect(StreamBuilderService.url(nvr, 8, password: 'test'), contains('/unicast/c8/s1/live'));
    final start = DateTime.utc(2026, 11, 19, 10);
    final end = start.add(const Duration(minutes: 2));
    final url = StreamBuilderService.url(nvr, 8, password: 'test', start: start, end: end)!;
    expect(Uri.parse(url).path, '/c8/b${start.millisecondsSinceEpoch ~/ 1000}/e${end.millisecondsSinceEpoch ~/ 1000}/replay/');
  });
  test('OEM protocol survives storage and controls MEye and Topcam playback', () {
    for (final brand in ['MEye', 'Topcam']) {
      for (final protocol in ['Dahua', 'Hikvision', 'Uniview']) {
        final nvr = Nvr.fromJson(device.copyWith(manufacturer: brand,
            streamProtocol: protocol).toJson());
        expect(nvr.manufacturer, brand);
        expect(nvr.streamProtocol, protocol);
        expect(StreamBuilderService.url(nvr, 2, password: 'test', start: DateTime(2026)),
            StreamBuilderService.url(device.copyWith(manufacturer: protocol), 2,
                password: 'test', start: DateTime(2026)));
      }
    }
  });
  test('Xiongmai live escapes credentials; unsupported playback is explicit', () {
    final nvr = device.copyWith(manufacturer: 'MEye');
    expect(StreamBuilderService.url(nvr, 3, password: 'a&b'),
        contains('user=test%20user&password=a%26b&channel=3&stream=1.sdp?real_stream'));
    expect(StreamBuilderService.alternate(nvr, 3, password: 'a&b'),
        contains('user=test%20user_password=a%26b_channel=3_stream=1.sdp'));
    expect(StreamBuilderService.url(nvr, 3, password: 'test', start: DateTime(2026)), isNull);
  });
  test('invalid channel or reversed recording range never opens another camera', () {
    for (final brand in manufacturers) {
      final nvr = device.copyWith(manufacturer: brand);
      expect(StreamBuilderService.url(nvr, 0, password: 'test'), isNull);
      expect(StreamBuilderService.url(nvr, 9, password: 'test'), isNull);
      expect(StreamBuilderService.url(nvr, 1, password: 'test',
          start: DateTime(2026, 2), end: DateTime(2026)), isNull);
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
