import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Desktop screen/window picker for host screen sharing.
class ScreenSelectDialog extends StatefulWidget {
  const ScreenSelectDialog({super.key});

  @override
  State<ScreenSelectDialog> createState() => _ScreenSelectDialogState();
}

class _ScreenSelectDialogState extends State<ScreenSelectDialog> {
  SourceType _sourceType = SourceType.Screen;
  List<DesktopCapturerSource> _sources = [];
  DesktopCapturerSource? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _loading = true);
    try {
      final sources = await desktopCapturer.getSources(types: [_sourceType]);
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _selected = sources.isNotEmpty ? sources.first : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择共享内容'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<SourceType>(
              segments: const [
                ButtonSegment(
                  value: SourceType.Screen,
                  label: Text('整个屏幕'),
                  icon: Icon(Icons.desktop_windows),
                ),
                ButtonSegment(
                  value: SourceType.Window,
                  label: Text('窗口'),
                  icon: Icon(Icons.web_asset),
                ),
              ],
              selected: {_sourceType},
              onSelectionChanged: (value) {
                _sourceType = value.first;
                _loadSources();
              },
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_sources.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('未找到可共享的屏幕或窗口'),
              )
            else
              SizedBox(
                height: 240,
                child: ListView.builder(
                  itemCount: _sources.length,
                  itemBuilder: (context, index) {
                    final source = _sources[index];
                    return RadioListTile<DesktopCapturerSource>(
                      value: source,
                      groupValue: _selected,
                      title: Text(source.name),
                      subtitle: Text(
                        source.type == SourceType.Screen ? '屏幕' : '窗口',
                      ),
                      onChanged: (value) => setState(() => _selected = value),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
          child: const Text('开始共享'),
        ),
      ],
    );
  }
}
