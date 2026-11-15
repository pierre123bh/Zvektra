import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvektra/main.dart';

class PendingDeviceStore extends DeviceStore {
  final pendingReads = <Completer<String?>>[];

  PendingDeviceStore() {
    devices = [
      const Nvr(
        id: 'shop',
        name: 'Shop',
        manufacturer: 'Dahua',
        port: '16554',
        username: 'test',
        maxChannels: 4,
      ),
    ];
  }

  @override
  Future<String?> password(String id) {
    final pending = Completer<String?>();
    pendingReads.add(pending);
    return pending.future;
  }
}

void main() {
  testWidgets('Pause cancels a pending startup; Resume starts a fresh request',
      (tester) async {
    final store = PendingDeviceStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AssistantScreen(store: store)),
    ));

    final streamList = find.descendant(
      of: find.byType(ListView), matching: find.byType(Scrollable),
    ).first;
    await tester.ensureVisible(find.text('Live'));
    await tester.tap(find.text('Live'));
    await tester.pump();
    expect(store.pendingReads.length, 1);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    store.pendingReads.first.complete(null);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Connection cancelled.').first, 120, scrollable: streamList,
    );
    expect(find.text('Connection cancelled.'), findsWidgets);
    expect(find.text('Edit the NVR and enter its password.'), findsNothing);

    await tester.ensureVisible(find.text('Resume'));
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(store.pendingReads.length, 2);
    store.pendingReads.last.complete(null);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Edit the NVR and enter its password.').first, 120,
      scrollable: streamList,
    );
    expect(find.text('Edit the NVR and enter its password.'), findsWidgets);
  });
}
