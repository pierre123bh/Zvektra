import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zvektra/main.dart';

void main() {
  testWidgets('failed save keeps the form open and retry persists the NVR',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final passwords = <String, String>{};
    var failWrite = true;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final key = call.arguments['key'] as String;
      switch (call.method) {
        case 'write':
          if (failWrite) throw PlatformException(code: 'storage unavailable');
          passwords[key] = call.arguments['value'] as String;
          return null;
        case 'read':
          return passwords[key];
        default:
          throw MissingPluginException(call.method);
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final store = DeviceStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DevicesScreen(store: store)),
    ));
    await tester.tap(find.text('Add NVR'));
    await tester.pumpAndSettle();
    expect(find.text('Hostname'), findsNothing);
    expect(find.text(host), findsNothing);

    final fields = find.byType(TextFormField);
    for (final entry in ['Shop', '01554', '8', 'test user', 'test password'].indexed) {
      await tester.ensureVisible(fields.at(entry.$1));
      await tester.enterText(fields.at(entry.$1), entry.$2);
    }

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the NVR. Try again.'), findsOneWidget);
    expect(store.devices, isEmpty);

    failWrite = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    final reloaded = DeviceStore();
    await reloaded.load();
    expect(reloaded.devices.single.name, 'Shop');
    expect(reloaded.devices.single.port, '1554');
    expect(await reloaded.password(reloaded.devices.single.id), 'test password');
  });
}
