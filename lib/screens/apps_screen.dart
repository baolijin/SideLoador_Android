import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/bridge_services.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({
    super.key,
    required this.device,
    required this.apps,
    required this.onBack,
  });

  final AdbDevice device;
  final List<AppInfo> apps;
  final VoidCallback onBack;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _query = '';
  AppInfo? _launching;

  List<AppInfo> get _thirdParty {
    final list = widget.apps.where((a) => a.isThirdParty).toList()
      ..sort((a, b) {
        final la = a.sortLetter.compareTo(b.sortLetter);
        if (la != 0) return la;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  List<AppInfo> get _filtered {
    final q = _query.trim().toLowerCase();
    final base = _thirdParty;
    if (q.isEmpty) return base;
    return base
        .where((a) =>
            a.name.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList();
  }

  List<String> get _letters {
    final set = <String>{};
    for (final a in _filtered) {
      set.add(a.sortLetter);
    }
    final ordered = <String>[];
    if (set.contains('#')) ordered.add('#');
    for (var c = 65; c <= 90; c++) {
      final ch = String.fromCharCode(c);
      if (set.contains(ch)) ordered.add(ch);
    }
    return ordered;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Launch immediately — no confirmation dialog.
  Future<void> _launch(AppInfo app) async {
    if (_launching != null) return;
    setState(() => _launching = app);
    try {
      final proc = await ScrcpyService().launchVirtualDisplay(
        serial: widget.device.serial,
        packageName: app.packageName,
      );
      // ignore: unawaited_futures
      proc.exitCode.then((code) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('scrcpy 退出 (code=$code) · ${app.name}')),
          );
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('虚拟屏已打开 · ${app.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _launching = null);
    }
  }

  void _jumpTo(String letter) {
    final list = _filtered;
    for (var i = 0; i < list.length; i++) {
      if (list[i].sortLetter == letter) {
        const cross = 8;
        final row = i ~/ cross;
        const itemExtent = 110.0;
        _scrollCtrl.animateTo(
          row * itemExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = _filtered;
    final letters = _letters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('设备'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4F8CFF),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF171B24),
                  border: Border.all(color: const Color(0xFF2A3140)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.device.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8B93A7),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Centered title + count
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '应用列表',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              '${apps.length} 个',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        // Search: 1/3 of screen width, centered
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth / 3;
              return SizedBox(
                width: w,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '搜索应用名称…',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF171B24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A3140)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A3140)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF4F8CFF)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: apps.isEmpty
                    ? Center(
                        child: Text(
                          '无匹配应用',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollCtrl,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                          childAspectRatio: 0.9,
                        ),
                        padding: const EdgeInsets.fromLTRB(4, 0, 2, 6),
                        itemCount: apps.length,
                        itemBuilder: (context, i) {
                          final app = apps[i];
                          return _AppTile(
                            app: app,
                            enabled: _launching == null,
                            onTap: () => _launch(app),
                          );
                        },
                      ),
              ),
              // Alphabet sidebar
              if (letters.isNotEmpty)
                SizedBox(
                  width: 22,
                  child: GestureDetector(
                    onVerticalDragUpdate: (d) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final local =
                          box.globalToLocal(d.globalPosition).dy;
                      final h = box.size.height;
                      if (h <= 0) return;
                      final idx =
                          ((local / h) * letters.length).clamp(0, letters.length - 1).round();
                      if (idx >= 0 && idx < letters.length) {
                        _jumpTo(letters[idx]);
                      }
                    },
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      children: [
                        for (final L in letters)
                          InkWell(
                            onTap: () => _jumpTo(L),
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              height: 22,
                              child: Center(
                                child: Text(
                                  L,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4F8CFF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.onTap,
    required this.enabled,
  });

  final AppInfo app;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final initial = app.name.isNotEmpty
        ? String.fromCharCode(app.name.runes.first).toUpperCase()
        : '?';

    // Icon ×1.2 → 48; label ×1.2 → ~13
    Widget icon;
    if (app.iconBytes != null && app.iconBytes!.isNotEmpty) {
      icon = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          app.iconBytes!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallbackIcon(initial),
        ),
      );
    } else {
      icon = _fallbackIcon(initial);
    }

    // Transparent card; icon + text centered in the tile.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 2),
              Text(
                app.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.2,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon(String initial) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF2A3140),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }
}
