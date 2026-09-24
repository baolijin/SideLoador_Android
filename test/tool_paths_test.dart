import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_bridge/services/bridge_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ToolPaths.adb resolves to an existing absolute binary', () {
    final adb = ToolPaths.adb;
    expect(adb.contains('/') || adb.contains(r'\'), isTrue,
        reason: 'expected absolute path, got: $adb');
    if (!Platform.isWindows) {
      expect(File(adb).existsSync(), isTrue, reason: 'adb not found at $adb');
    }
  });

  test('ToolPaths.scrcpy resolves to an existing absolute binary', () {
    final scrcpy = ToolPaths.scrcpy;
    expect(scrcpy.contains('/') || scrcpy.contains(r'\'), isTrue,
        reason: 'expected absolute path, got: $scrcpy');
    if (!Platform.isWindows) {
      expect(File(scrcpy).existsSync(), isTrue,
          reason: 'scrcpy not found at $scrcpy');
    }
  });

  test('childEnvironment PATH includes platform-tools', () {
    final path = ToolPaths.childEnvironment['PATH'] ?? '';
    expect(path.contains('platform-tools'), isTrue);
  });
}
