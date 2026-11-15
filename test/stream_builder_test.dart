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
}
