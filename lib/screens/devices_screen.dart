import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/bridge_services.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.onDeviceSelected});

  /// Called after install + app-list fetch succeed, with the list ready.
  final void Function(AdbDevice device, List<AppInfo> apps) onDeviceSelected;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _adb = AdbService();
  List<AdbDevice> _devices = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  bool _installing = false;
  double _installPct = 0;
  String _installStep = '';

  @override
  void initState() {
    super.initState();
    // Skip real adb I/O under widget tests to avoid pending Process timers.
    final inTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!inTest) {
      _refresh();
    } else {
      _loading = false;
      _devices = const [
        AdbDevice(serial: 'emulator-5554', state: 'device', model: 'Test Device'),
      ];
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _loading = _devices.isEmpty;
      _error = null;
    });
    try {
      final list = await _adb.listDevices();
      if (!mounted) return;
      setState(() => _devices = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _select(AdbDevice device) async {
    if (_installing || !device.isOnline) return;
    setState(() {
      _installing = true;
      _installPct = 0.05;
      _installStep = '检测设备连接状态…';
    });

    try {
      Future<void> step(double pct, String text) async {
        if (!mounted) return;
        setState(() {
          _installPct = pct;
          _installStep = text;
        });
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      await step(0.2, '定位 mobile-app APK…');
      final apk = await _locateMobileApk();
      if (apk == null) {
        throw Exception(
          '未找到 mobile-app APK。\n'
          '请确认 assets/scrcpy_bridge_mobile.apk 已打包，'
          '或设置环境变量 MOBILE_APK=/path/to.apk',
        );
      }

      await step(0.4, '安装 mobile-app…\n$apk');
      await _adb.installApk(device.serial, apk);

      await step(0.7, '采集应用列表…');
      final apps = await _adb.fetchAppList(device.serial);
      await step(1.0, '完成');

      if (!mounted) return;
      setState(() => _installing = false);
      // Pass apps in the same callback — never rely on a later global write.
      widget.onDeviceSelected(device, apps);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('部署失败: $e')),
      );
    }
  }

  /// Resolve APK for packaged .app (CWD is unreliable) and source builds.
  Future<String?> _locateMobileApk() async {
    final candidates = <String?>[
      Platform.environment['MOBILE_APK'],
      // Next to the executable / inside .app Resources
      '${File(Platform.resolvedExecutable).parent.path}/scrcpy_bridge_mobile.apk',
      '${File(Platform.resolvedExecutable).parent.path}/Resources/scrcpy_bridge_mobile.apk',
      _exeRelative('assets/scrcpy_bridge_mobile.apk'),
      _exeRelative('../Resources/scrcpy_bridge_mobile.apk'),
      // Source-tree fallbacks when running via `flutter run`
      '${Directory.current.path}/assets/scrcpy_bridge_mobile.apk',
      '${Directory.current.path}/mobile_app/app/build/outputs/apk/debug/app-debug.apk',
      '${Directory.current.path}/mobile_app/build/outputs/apk/debug/mobile_app-debug.apk',
    ];

    for (final c in candidates) {
      if (c != null && c.isNotEmpty && File(c).existsSync()) return c;
    }

    // Extract Flutter asset → temp file (works for packaged .app)
    try {
      final data = await rootBundle.load('assets/scrcpy_bridge_mobile.apk');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final tmp = Directory.systemTemp.createTempSync('scrcpy_bridge_');
      final out = File('${tmp.path}/scrcpy_bridge_mobile.apk');
      await out.writeAsBytes(bytes, flush: true);
      return out.path;
    } catch (_) {
      return null;
    }
  }

  String? _exeRelative(String rel) {
    try {
      final base = File(Platform.resolvedExecutable).parent.path;
      final p = '$base/$rel';
      if (File(p).existsSync()) return p;
      // .app/Contents/MacOS → .app/Contents/Resources
      final contents = File(Platform.resolvedExecutable).parent.parent.path;
      final p2 = '$contents/$rel';
      if (File(p2).existsSync()) return p2;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_installing) {
      return _InstallPanel(pct: _installPct, step: _installStep);
    }

    // Device list content is half of the window width, centered.
    return LayoutBuilder(
      builder: (context, constraints) {
        final listWidth = constraints.maxWidth / 2;
        return Center(
          child: SizedBox(
            width: listWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Android 设备',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'adb devices · 点击设备部署 mobile-app',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _refreshing ? null : _refresh,
                        tooltip: '刷新设备列表',
                        icon: _refreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x1AFF6B6B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x44FF6B6B)),
                    ),
                    child: Text(
                      _error!,
                      style:
                          const TextStyle(fontSize: 12, color: Color(0xFFFF8A8A)),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _devices.isEmpty
                          ? const _EmptyDevices()
                          : ListView.separated(
                              itemCount: _devices.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final d = _devices[i];
                                return _DeviceCard(
                                  device: d,
                                  onTap: () => _select(d),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});

  final AdbDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final online = device.isOnline;
    return Material(
      color: const Color(0xFF171B24),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: online ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A3140)),
          ),
          child: Opacity(
            opacity: online ? 1 : 0.55,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0x244F8CFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.phone_android,
                      color: Color(0xFF4F8CFF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        device.serial,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFF8B93A7),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: online
                        ? const Color(0x1F3DD68C)
                        : const Color(0x1F8B93A7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    device.state.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color:
                          online ? const Color(0xFF3DD68C) : const Color(0xFF8B93A7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phonelink_off,
              size: 40, color: Colors.white.withValues(alpha: 0.35)),
          const SizedBox(height: 10),
          const Text('未发现设备',
              style: TextStyle(fontSize: 14, color: Color(0xFF8B93A7))),
          const SizedBox(height: 4),
          Text(
            '请连接设备并开启 USB 调试',
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}

class _InstallPanel extends StatelessWidget {
  const _InstallPanel({required this.pct, required this.step});

  final double pct;
  final String step;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct.clamp(0, 1)),
            duration: const Duration(milliseconds: 400),
            builder: (context, v, _) => SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: v,
                    strokeWidth: 4,
                    color: const Color(0xFF4F8CFF),
                    backgroundColor: const Color(0xFF1E2430),
                  ),
                  const Center(
                    child:
                        Icon(Icons.phone_android, color: Color(0xFF4F8CFF)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '正在部署 Mobile App',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            step,
            style: const TextStyle(fontSize: 13, color: Color(0xFF8B93A7)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pct.clamp(0, 1),
                minHeight: 4,
                backgroundColor: const Color(0xFF1E2430),
                color: const Color(0xFF4F8CFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
