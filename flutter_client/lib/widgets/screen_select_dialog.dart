import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../utils/thumbnail_utils.dart';

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
  final Map<String, Uint8List> _thumbnails = {};
  final Set<String> _loadingThumbnailIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _sources = [];
      _selected = null;
      _thumbnails.clear();
      _loadingThumbnailIds.clear();
    });

    try {
      final sources = await desktopCapturer.getSources(
        types: [_sourceType],
        thumbnailSize: ThumbnailSize(480, 270),
      );
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _selected = sources.isNotEmpty ? sources.first : null;
        _loading = false;
      });
      for (final source in sources) {
        unawaited(_loadThumbnail(source));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadThumbnail(DesktopCapturerSource source) async {
    if (_thumbnails.containsKey(source.id) || _loadingThumbnailIds.contains(source.id)) {
      return;
    }
    setState(() => _loadingThumbnailIds.add(source.id));
    final bytes = await ThumbnailUtils.loadForSource(source);
    if (!mounted) return;
    setState(() {
      _loadingThumbnailIds.remove(source.id);
      if (bytes != null) {
        _thumbnails[source.id] = bytes;
      }
    });
  }

  void _selectSource(DesktopCapturerSource source) {
    setState(() => _selected = source);
    unawaited(_loadThumbnail(source));
  }

  Widget _thumbnailImage(String sourceId, {BoxFit fit = BoxFit.cover}) {
    final bytes = _thumbnails[sourceId];
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white38),
        ),
      );
    }
    if (_loadingThumbnailIds.contains(sourceId)) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.white38));
  }

  Widget _buildPreview() {
    final selected = _selected;
    return SizedBox(
      height: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: selected == null
              ? const Center(child: Text('请选择要共享的屏幕或窗口'))
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    _thumbnailImage(selected.id),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      right: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            selected.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;

    return AlertDialog(
      title: const Text('选择共享内容'),
      content: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
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
                _buildPreview(),
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
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _sources.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final source = _sources[index];
                      final isSelected = _selected?.id == source.id;
                      return Material(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _selectSource(source),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    width: 96,
                                    height: 54,
                                    child: _thumbnailImage(source.id),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        source.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        source.type == SourceType.Screen ? '屏幕' : '窗口',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
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
