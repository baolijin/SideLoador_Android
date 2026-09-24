import 'dart:typed_data';

class AdbDevice {
  final String serial;
  final String state;
  final String? model;
  final String? product;

  const AdbDevice({
    required this.serial,
    required this.state,
    this.model,
    this.product,
  });

  bool get isOnline => state == 'device';

  String get displayName {
    if (model != null && model!.isNotEmpty) return model!;
    if (product != null && product!.isNotEmpty) return product!;
    return serial;
  }

  factory AdbDevice.fromAdbLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    final serial = parts.isNotEmpty ? parts[0] : '';
    final state = parts.length > 1 ? parts[1] : 'unknown';
    return AdbDevice(serial: serial, state: state);
  }
}

class AppInfo {
  final String name;
  final String packageName;
  final int colorValue;
  final bool isThirdParty;
  /// Decoded original icon PNG bytes (from mobile-app), if available.
  final Uint8List? iconBytes;

  const AppInfo({
    required this.name,
    required this.packageName,
    this.colorValue = 0xFF4F8CFF,
    this.isThirdParty = true,
    this.iconBytes,
  });

  /// Sort key: A-Z letter, else '#'.
  String get sortLetter {
    if (name.isEmpty) return '#';
    final ch = name.runes.first;
    final c = String.fromCharCode(ch).toUpperCase();
    final code = c.codeUnitAt(0);
    if (code >= 65 && code <= 90) return c;
    // Digit
    if (code >= 48 && code <= 57) return '#';
    return '#';
  }
}
