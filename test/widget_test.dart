import 'package:flutter_test/flutter_test.dart';

import 'package:scrcpy_bridge/main.dart';

void main() {
  testWidgets('app boots to device list', (WidgetTester tester) async {
    await tester.pumpWidget(const ScrcpyBridgeApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Custom Flutter title bar removed — native OS title only.
    expect(find.text('Scrcpy Bridge'), findsNothing);
    expect(find.text('Android 设备'), findsOneWidget);
    expect(find.byTooltip('刷新设备列表'), findsOneWidget);
  });
}
