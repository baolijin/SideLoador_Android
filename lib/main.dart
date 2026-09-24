import 'dart:io';

import 'package:flutter/material.dart';

import 'models/models.dart';
import 'screens/apps_screen.dart';
import 'screens/devices_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScrcpyBridgeApp());
}

class ScrcpyBridgeApp extends StatelessWidget {
  const ScrcpyBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SideLoador-Android',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F8CFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF0F1218),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1218),
        fontFamily: Platform.isMacOS ? '.SF NS Text' : null,
      ),
      // Full window content — OS provides the window chrome / rounded corners.
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  AdbDevice? _device;
  List<AppInfo> _apps = const [];
  bool _showApps = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _showApps && _device != null
                    ? AppsScreen(
                        key: const ValueKey('apps'),
                        device: _device!,
                        apps: _apps,
                        onBack: () => setState(() => _showApps = false),
                      )
                    : DevicesScreen(
                        key: const ValueKey('devices'),
                        onDeviceSelected: (d, apps) {
                          setState(() {
                            _device = d;
                            _apps = List.of(apps);
                            _showApps = true;
                          });
                        },
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF171B24),
                border: Border(top: BorderSide(color: Color(0xFF2A3140))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3DD68C),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'ADB ready',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      _showApps
                          ? 'scrcpy --new-display'
                          : 'desktop-app · win/linux/mac',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
