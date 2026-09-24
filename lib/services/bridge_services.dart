import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/models.dart';

/// Resolves adb / scrcpy binaries across platforms and PATH conventions.
///
/// Resolution order:
/// 1. Env (`ADB_PATH` / `SCRCPY_PATH`)
/// 2. **Bundled tools** next to the executable (`tools/adb`, `tools/scrcpy`)
/// 3. Common host install locations
/// 4. Login-shell `command -v`
class ToolPaths {
  static String? _adb;
  static String? _scrcpy;

  /// Directory that contains bundled `tools/` (adb, scrcpy, dylibs).
  static String get _exeDir {
    try {
      return File(Platform.resolvedExecutable).parent.path;
    } catch (_) {
      return '.';
    }
  }

  static String? _bundled(String name) {
    final names = <String>[name];
    if (Platform.isWindows) {
      if (!name.toLowerCase().endsWith('.exe')) names.add('$name.exe');
    } else {
      if (name.toLowerCase().endsWith('.exe')) {
        names.add(name.substring(0, name.length - 4));
      }
    }

    for (final n in names) {
      final candidates = <String>[
        '$_exeDir/tools/$n',
        '$_exeDir/../Resources/tools/$n',
        // flutter run / source tree
        '${Directory.current.path}/build/tools/$n',
      ];
      for (final c in candidates) {
        try {
          if (File(c).existsSync()) return File(c).absolute.path;
        } catch (_) {}
      }
    }
    return null;
  }

  static String get adb {
    return _adb ??= _resolveTool(
      envKey: 'ADB_PATH',
      bareName: 'adb',
      bareNameWin: 'adb.exe',
      bundledName: Platform.isWindows ? 'adb.exe' : 'adb',
      absoluteCandidates: [
        _joinHome('Library/Android/sdk/platform-tools/adb'),
        _joinHome('Android/Sdk/platform-tools/adb'),
        '/Users/admin/Library/Android/sdk/platform-tools/adb',
        '/opt/homebrew/bin/adb',
        '/usr/local/bin/adb',
        '/usr/bin/adb',
        '/usr/lib/android-sdk/platform-tools/adb',
        r'C:\Android\platform-tools\adb.exe',
        r'C:\Users\Public\platform-tools\adb.exe',
        r'C:\Program Files\platform-tools\adb.exe',
      ],
    );
  }

  static String get scrcpy {
    return _scrcpy ??= _resolveTool(
      envKey: 'SCRCPY_PATH',
      bareName: 'scrcpy',
      bareNameWin: 'scrcpy.exe',
      bundledName: Platform.isWindows ? 'scrcpy.exe' : 'scrcpy',
      absoluteCandidates: [
        '/opt/homebrew/bin/scrcpy',
        '/usr/local/bin/scrcpy',
        '/usr/bin/scrcpy',
        '/usr/local/scrcpy/scrcpy',
        _joinHome('Library/Android/sdk/cmdline-tools/latest/bin/scrcpy'),
        r'C:\Program Files\scrcpy\scrcpy.exe',
        r'C:\scrcpy\scrcpy.exe',
        r'C:\Program Files (x86)\scrcpy\scrcpy.exe',
      ],
    );
  }

  /// Extra PATH entries for child processes.
  /// Bundled tools dir comes first so sibling dylibs/so/dll resolve.
  static Map<String, String> get childEnvironment {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final bundledDir = '$_exeDir/tools';
    final pathParts = <String>[
      if (Directory(bundledDir).existsSync()) bundledDir,
      if (Platform.environment['PATH'] != null) Platform.environment['PATH']!,
      if (!Platform.isWindows) ...[
        _joinHome('Library/Android/sdk/platform-tools'),
        _joinHome('Android/Sdk/platform-tools'),
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/usr/lib/android-sdk/platform-tools',
        if (home.isNotEmpty) '$home/bin',
      ] else ...[
        r'C:\Android\platform-tools',
        r'C:\Users\Public\platform-tools',
        if (home.isNotEmpty) '$home\\bin',
      ],
    ];

    final env = <String, String>{
      ...Platform.environment,
      'PATH': pathParts.join(Platform.isWindows ? ';' : ':'),
    };

    if (Platform.isMacOS) {
      env['DYLD_LIBRARY_PATH'] = [
        if (Directory('$_exeDir/tools/lib').existsSync()) '$_exeDir/tools/lib',
        if (Directory('$_exeDir/tools').existsSync()) '$_exeDir/tools',
        if (Platform.environment['DYLD_LIBRARY_PATH'] != null)
          Platform.environment['DYLD_LIBRARY_PATH']!,
      ].join(':');
    } else if (Platform.isLinux) {
      env['LD_LIBRARY_PATH'] = [
        if (Directory('$_exeDir/tools/lib').existsSync()) '$_exeDir/tools/lib',
        if (Directory('$_exeDir/tools').existsSync()) '$_exeDir/tools',
        if (Platform.environment['LD_LIBRARY_PATH'] != null)
          Platform.environment['LD_LIBRARY_PATH']!,
      ].join(':');
    }

    return env;
  }

  static String _joinHome(String rel) {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return home.isEmpty ? rel : '$home/$rel';
  }

  static String _resolveTool({
    required String envKey,
    required String bareName,
    required String bareNameWin,
    required String bundledName,
    required List<String> absoluteCandidates,
  }) {
    final env = Platform.environment[envKey];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return env;
    }

    // Bundled tools first (host-agnostic package).
    final bundled = _bundled(bundledName);
    if (bundled != null) return bundled;

    for (final c in absoluteCandidates) {
      if (c.isEmpty) continue;
      if (File(c).existsSync()) return c;
    }

    final shellHit = _whichFromLoginShell(bareName) ??
        _whichFromLoginShell(bareNameWin);
    if (shellHit != null) return shellHit;

    return Platform.isWindows ? bareNameWin : bareName;
  }

  static String? _whichFromLoginShell(String bin) {
    try {
      final shell = Platform.isWindows ? 'where' : '/bin/zsh';
      final args = Platform.isWindows
          ? <String>[bin]
          : <String>['-lc', 'command -v $bin || true'];
      if (Platform.isWindows && shell == 'where') {
        final r = Process.runSync(
          'where',
          [bin],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        final line = (r.stdout as String)
            .split('\n')
            .map((s) => s.trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        return line.isEmpty ? null : line;
      }
      final r = Process.runSync(
        shell,
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final line = (r.stdout as String)
          .split('\n')
          .map((s) => s.trim())
          .firstWhere((s) => s.isNotEmpty && !s.contains('not found'),
              orElse: () => '');
      if (line.isEmpty || r.exitCode != 0) return null;
      if (File(line).existsSync()) return line;
      return null;
    } catch (_) {
      return null;
    }
  }
}

class AdbService {
  Future<ProcessResult> _run(List<String> args,
      {Duration timeout = const Duration(seconds: 20)}) {
    final exe = ToolPaths.adb;
    try {
      return Process.run(
        exe,
        args,
        environment: ToolPaths.childEnvironment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
    } on ProcessException catch (e) {
      throw Exception(
        '无法启动 adb。\n'
        '路径: $exe\n'
        '原因: ${e.message}\n'
        '请设置 ADB_PATH，或确认 Android SDK platform-tools 已安装。',
      );
    } on TimeoutException {
      throw Exception('adb 超时: $exe ${args.join(' ')}');
    }
  }

  /// `adb devices` → list of devices (with model via getprop when online).
  Future<List<AdbDevice>> listDevices() async {
    final result = await _run(['devices', '-l']);
    if (result.exitCode != 0) {
      throw Exception('adb devices failed: ${result.stderr}');
    }

    final devices = <AdbDevice>[];
    for (final line in (result.stdout as String).split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('List of devices')) continue;
      if (t.startsWith('*')) continue;
      final base = AdbDevice.fromAdbLine(t);

      String? model;
      String? product;
      // parse extra key:value tokens from -l output
      final tokens = t.split(RegExp(r'\s+'));
      for (final tok in tokens) {
        if (tok.startsWith('model:')) model = tok.substring(6);
        if (tok.startsWith('product:')) product = tok.substring(8);
      }

      if (base.isOnline && model == null) {
        model = await _deviceModel(base.serial);
      }

      devices.add(AdbDevice(
        serial: base.serial,
        state: base.state,
        model: model,
        product: product,
      ));
    }
    return devices;
  }

  Future<String?> _deviceModel(String serial) async {
    try {
      final r = await _run([
        '-s',
        serial,
        'shell',
        'getprop',
        'ro.product.model',
      ], timeout: const Duration(seconds: 8));
      final s = (r.stdout as String).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<void> installApk(String serial, String apkPath) async {
    if (!File(apkPath).existsSync()) {
      throw Exception('APK 不存在: $apkPath');
    }
    final r = await _run(
      ['-s', serial, 'install', '-r', '-t', apkPath],
      timeout: const Duration(seconds: 120),
    );
    final out = '${r.stdout}\n${r.stderr}'.trim();
    // adb often returns 0 with "Success" on stdout; Failure may still appear.
    final ok = r.exitCode == 0 && out.contains('Success');
    final failure = out.contains('Failure') || out.contains('Error');
    if (!ok || failure) {
      throw Exception(
        'APK 安装失败 (exit=${r.exitCode})\n'
        '路径: $apkPath\n'
        '输出:\n$out',
      );
    }
  }

  Future<String> shell(String serial, List<String> cmd,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final r = await _run(['-s', serial, 'shell', ...cmd], timeout: timeout);
    if (r.exitCode != 0) {
      final stdout = (r.stdout ?? '').toString();
      final stderr = (r.stderr ?? '').toString();
      // MIUI often returns 255 with empty streams for `pm`; still surface the argv.
      throw Exception(
        'shell failed (exit=${r.exitCode})\n'
        'cmd: adb -s $serial shell ${cmd.join(' ')}\n'
        'stdout: ${stdout.isEmpty ? '(empty)' : stdout}\n'
        'stderr: ${stderr.isEmpty ? '(empty)' : stderr}',
      );
    }
    return (r.stdout ?? '').toString().trim();
  }

  /// Like [shell], but never throws — returns null on failure.
  Future<String?> tryShell(String serial, List<String> cmd,
      {Duration timeout = const Duration(seconds: 45)}) async {
    try {
      return await shell(serial, cmd, timeout: timeout);
    } catch (_) {
      return null;
    }
  }

  /// Fetch third-party apps only (with original icons when mobile-app provides them).
  Future<List<AppInfo>> fetchAppList(String serial) async {
    // 1) Start helper
    await tryShell(serial, [
      'am',
      'start',
      '-W',
      '-n',
      'com.scrcpy.bridge/.MainActivity',
    ], timeout: const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final byPkg = <String, AppInfo>{};
    const absJson = '/data/data/com.scrcpy.bridge/files/scrcpy_apps.json';
    for (final args in [
      ['run-as', 'com.scrcpy.bridge', 'cat', absJson],
      ['run-as', 'com.scrcpy.bridge', 'sh', '-c', 'cat $absJson'],
      ['cat', '/data/local/tmp/scrcpy_apps.json'],
    ]) {
      final json = await tryShell(serial, args, timeout: const Duration(seconds: 60));
      if (json == null || json.isEmpty) continue;
      final apps = _parseAppsJson(json);
      if (apps.isEmpty) continue;
      for (final a in apps) {
        if (a.isThirdParty) byPkg[a.packageName] = a;
      }
      break;
    }

    // 2) Ensure complete third-party set from shell
    final thirdParty = <String>{};
    for (final args in [
      ['cmd', 'package', 'list', 'packages', '-3'],
      ['pm', 'list', 'packages', '-3'],
    ]) {
      final out = await tryShell(serial, args);
      if (out == null || out.isEmpty) continue;
      for (final line in out.split('\n')) {
        final p = line.trim().replaceFirst('package:', '');
        if (p.contains('.')) thirdParty.add(p);
      }
      if (thirdParty.isNotEmpty) break;
    }

    for (final p in thirdParty) {
      byPkg.putIfAbsent(
        p,
        () => AppInfo(
          name: _prettyName(p),
          packageName: p,
          colorValue: _colorFor(p),
          isThirdParty: true,
        ),
      );
    }

    // Third-party only
    final list = byPkg.values.where((a) => a.isThirdParty).toList()
      ..sort((a, b) {
        final la = a.sortLetter.compareTo(b.sortLetter);
        if (la != 0) return la;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (list.isEmpty) {
      throw Exception(
        '未找到第三方应用。\n'
        '已尝试: mobile-app JSON / cmd package -3。\n'
        '请确认设备已连接，且 mobile-app 安装成功。',
      );
    }
    return list;
  }

  String _prettyName(String packageName) {
    final last = packageName.split('.').last;
    if (last.isEmpty) return packageName;
    return last[0].toUpperCase() + last.substring(1);
  }

  List<AppInfo> _parseAppsJson(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return [];
    final cleaned = raw.substring(start, end + 1);
    try {
      final list = jsonDecode(cleaned) as List<dynamic>;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        final system = m['system'] == true;
        Uint8List? iconBytes;
        final icon = m['icon'];
        if (icon is String && icon.isNotEmpty) {
          try {
            iconBytes = base64Decode(icon);
          } catch (_) {
            iconBytes = null;
          }
        }
        return AppInfo(
          name: (m['name'] as String?) ?? (m['packageName'] as String?) ?? '?',
          packageName: (m['packageName'] as String?) ?? '',
          colorValue: 0xFF4F8CFF,
          isThirdParty: !system,
          iconBytes: iconBytes,
        );
      }).where((a) => a.packageName.isNotEmpty && a.isThirdParty).toList();
    } catch (_) {
      return [];
    }
  }

  int _colorFor(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = 0x1f1f1f * h + c;
    }
    const colors = [
      0xFF4285F4,
      0xFF07C160,
      0xFFE74C3C,
      0xFFFB7299,
      0xFFFF8800,
      0xFF1677FF,
      0xFF3DD68C,
      0xFF9C27B0,
    ];
    return colors[h.abs() % colors.length];
  }
}

class ScrcpyService {
  /// Launch app on a new virtual display (native scrcpy flags).
  Future<Process> launchVirtualDisplay({
    required String serial,
    required String packageName,
  }) async {
    final args = [
      '-s',
      serial,
      '--new-display',
      '--no-vd-system-decorations',
      '--display-ime-policy=local',
      '--start-app=$packageName',
    ];
    final cmd = '${ToolPaths.scrcpy} ${args.join(' ')}';
    // ignore: avoid_print
    print('[scrcpy] $cmd');
    return Process.start(
      ToolPaths.scrcpy,
      args,
      environment: ToolPaths.childEnvironment,
    );
  }

  static String buildCommand({
    required String serial,
    required String packageName,
  }) {
    return 'scrcpy -s $serial --new-display --no-vd-system-decorations '
        '--display-ime-policy=local --start-app=$packageName';
  }
}
